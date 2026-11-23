#!/usr/bin/env bash
#
# Builds the bitstreams and prints a summary of resource utilisation and timing.
#
#   ./build.sh lattice      X32 with Lattice ECP5   (Diamond, runs on this machine)
#   ./build.sh xilinx       X32 with Spartan-3A     (ISE 14.7, runs over SSH in the ISE VM)
#   ./build.sh all          both, in parallel
#   ./build.sh litex        only the LiteX components (register maps), no FPGA build
#
# Before the FPGA builds the LiteX components are generated for both families: the
# register bridge of the AES67 core (ext/AES67/litex_soc/build/aes67_bridge_<family>/,
# PTP servo and metering without CSRs) and the control SoC (litex_soc/build/).
#
# Environment:
#
#   LITEX_PYTHON      Python with LiteX, default: litex_soc/.venv/bin/python
#                     (created by litex_soc/setup_venv.sh if missing)
#   DIAMOND_DIR       Lattice Diamond installation, e.g. ~/lscc/diamond/3.14
#
#   ISE_VM_HOST       host name or IP address of the ISE VM
#   ISE_VM_REPO       path of this repository inside the VM, e.g. ~/OpenMixerProject/OpenAudioFPGA
#   ISE_VM_USER       optional, default: ise
#   ISE_VM_PASSWORD   optional, default: xilinx (the password of the official ISE VM);
#                     SSH keys are tried first
#   ISE_VM_SETTINGS   optional, default: /opt/Xilinx/14.7/ISE_DS/settings64.sh
#   ISE_VM_AES67_DIR  optional: path of the AES67 checkout inside the VM, if ext/AES67
#                     (symlink) does not resolve there; only needed with G_AES67
#
# Results (bit files, reports, logs) are collected in build/.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/build"

usage() {
	sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
	exit 1
}

die() {
	echo "build.sh: $*" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# control SoC (LiteX, Verilog for both families)
# ---------------------------------------------------------------------------
generate_soc() {
	local py="${LITEX_PYTHON:-$ROOT/litex_soc/.venv/bin/python}"
	if [ ! -x "$py" ] && [ -z "${LITEX_PYTHON:-}" ]; then
		echo "LiteX:   setting up litex_soc/.venv ..."
		"$ROOT/litex_soc/setup_venv.sh" || die "litex_soc/setup_venv.sh failed"
	fi
	[ -x "$py" ] || die "no Python with LiteX at $py"

	local aes67="$ROOT/ext/AES67/litex_soc/generate.py" family
	[ -f "$aes67" ] || die "AES67 core not found (git submodule update --init ext/AES67)"
	echo "LiteX:   generating the AES67 register bridge (log: build/aes67_bridge.log) ..."
	: >"$OUT/aes67_bridge.log"
	for family in lattice xilinx; do
		"$py" "$aes67" --target aes67_bridge --family $family --no-servo-csr --no-metering-csr \
			--no-hw-ptp-csr --no-ctrl-csr \
			>>"$OUT/aes67_bridge.log" 2>&1 \
			|| { tail -20 "$OUT/aes67_bridge.log"; die "AES67 generate.py ($family) failed"; }
	done

	echo "LiteX:   generating the control SoC (log: build/litex_soc.log) ..."
	"$py" "$ROOT/litex_soc/generate.py" --family all >"$OUT/litex_soc.log" 2>&1 \
		|| { tail -20 "$OUT/litex_soc.log"; die "litex_soc/generate.py failed"; }
}

# ---------------------------------------------------------------------------
# Lattice
# ---------------------------------------------------------------------------
check_lattice() {
	[ -n "${DIAMOND_DIR:-}" ] || die "DIAMOND_DIR is not set (Lattice Diamond installation, e.g. ~/lscc/diamond/3.14)"
	[ -x "$DIAMOND_DIR/bin/lin64/diamondc" ] || die "no bin/lin64/diamondc in DIAMOND_DIR=$DIAMOND_DIR"
}

build_lattice() {
	local dir="$ROOT/platforms/x32_lattice" impl="$ROOT/platforms/x32_lattice/impl1"
	rm -rf "$impl"
	(
		cd "$dir" || exit 1
		export bindir="$DIAMOND_DIR/bin/lin64"
		# diamond_env reads variables that may be unset
		set +u
		# shellcheck disable=SC1091
		source "$bindir/diamond_env" >/dev/null 2>&1
		"$bindir/diamondc" build.tcl bit
	) >"$OUT/x32_lattice.log" 2>&1
	local rc=$?
	cp "$impl/x32_lattice_impl1.mrp" "$OUT/x32_lattice.mrp" 2>/dev/null
	cp "$impl/x32_lattice_impl1.twr" "$OUT/x32_lattice.twr" 2>/dev/null
	cp "$impl/x32_lattice_impl1.bit" "$OUT/x32_lattice.bit" 2>/dev/null
	return $rc
}

# ---------------------------------------------------------------------------
# Xilinx (in the VM)
# ---------------------------------------------------------------------------
check_xilinx() {
	[ -n "${ISE_VM_HOST:-}" ] || die "ISE_VM_HOST is not set (host name or IP address of the ISE VM)"
	[ -n "${ISE_VM_REPO:-}" ] || die "ISE_VM_REPO is not set (path of this repository inside the VM)"
}

# vm <command>: runs a command in the VM. The official ISE VM is a CentOS 6
# and only offers SSH algorithms that current clients have switched off.
vm() {
	local opts=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new
		-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
		-o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1,diffie-hellman-group1-sha1)
	SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
		ssh "${opts[@]}" -o PreferredAuthentications=publickey,password -o NumberOfPasswordPrompts=1 \
		"${ISE_VM_USER:-ise}@$ISE_VM_HOST" "$@" </dev/null
}

build_xilinx() {
	local settings="${ISE_VM_SETTINGS:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}"
	# a leading ~ is the home directory in the VM
	local dir="${ISE_VM_REPO/#\~/\$HOME}/platforms/x32_spartan"
	local aes67_env=""
	[ -n "${ISE_VM_AES67_DIR:-}" ] && aes67_env="AES67_DIR=\"${ISE_VM_AES67_DIR/#\~/\$HOME}\" "
	vm "source \"$settings\" >/dev/null && cd \"$dir\" && rm -rf build && ${aes67_env}xtclsh create_project.tcl build" \
		>"$OUT/x32_spartan.log" 2>&1
	local rc=$?
	# ISE reports success in the log, xtclsh does not return it
	grep -q 'Process "Generate Programming File" completed successfully' "$OUT/x32_spartan.log" || rc=1
	vm "cat \"$dir/build/x32_spartan_map.mrp\"" >"$OUT/x32_spartan.mrp" 2>/dev/null
	vm "cat \"$dir/build/x32_spartan.twr\"" >"$OUT/x32_spartan.twr" 2>/dev/null
	vm "cat \"$dir/build/x32_spartan.bit\"" >"$OUT/x32_spartan.bit" 2>/dev/null
	[ -s "$OUT/x32_spartan.bit" ] || { rm -f "$OUT/x32_spartan.bit"; rc=1; }
	return $rc
}

# ---------------------------------------------------------------------------
# summaries
# ---------------------------------------------------------------------------
summary_lattice() {
	python3 - "$OUT/x32_lattice.mrp" "$OUT/x32_lattice.twr" <<'PY'
import re, sys
mrp = open(sys.argv[1], errors="replace").read() if len(sys.argv) > 1 else ""
try:
    twr = open(sys.argv[2], errors="replace").read()
except OSError:
    twr = ""

print("  Resources")
for label, pat in [
    ("Registers", r"Number of registers:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("Slices", r"Number of SLICEs:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("LUT4", r"Number of LUT4s:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("Block RAM (EBR)", r"Number of block RAMs:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("IO pins", r"Number of PIO sites used:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("PLLs", r"Number of PLLs:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
]:
    m = re.search(pat, mrp)
    if m:
        print("    %-18s %6s of %6s  %3s%%" % (label, m.group(1), m.group(2), m.group(3)))
m = re.search(r"^\s*MULT18X18D\s+(\d+)", mrp, re.M)
if m:
    print("    %-18s %6s" % ("MULT18X18D", m.group(1)))

def table(section):
    """rows (preference, constraint, actual, failed) of one 'Report Summary' table"""
    rows, name = [], ""
    for line in section.splitlines():
        if line.count("|") < 3:
            continue
        raw = line.split("|")
        cells = [c.strip() for c in raw]
        if cells[0].startswith("Preference"):
            continue
        # long names are wrapped at the column width, in the middle of a word
        name += raw[0] if len(raw[0].rstrip()) == len(raw[0]) else raw[0].rstrip() + " "
        if cells[1] == "" and cells[2] == "":
            if not cells[0]:
                name = ""
            continue
        failed = line.rstrip().endswith("*")
        rows.append((" ".join(name.split()).rstrip(";").strip(), cells[1], cells[2], failed))
        name = ""
    return rows

def short(name):
    name = re.sub(r"\s+[\d.]+ (MHz|X)$", "", name)
    name = re.sub(r"^FREQUENCY\s*", "", name) or "(all other clocks)"
    return name if len(name) <= 60 else "..." + name[-57:]

print("  Timing")
if not twr:
    print("    no timing report")
sections = twr.split("Report Summary")[1:]
for title, section in zip(("setup", "hold"), sections):
    section = section.split("Clock Domains Analysis")[0]
    rows = [r for r in table(section) if r[1] not in ("-", "")]
    bad = [r for r in rows if r[3]]
    print("    %s: %s" % (title, "%d preference(s) NOT met" % len(bad) if bad else "all preferences met"))
    for name, want, got, failed in rows:
        if failed:
            print("      %-60s %12s -> %12s  <-- not met" % (short(name), want, got))
        elif title == "setup" and name.startswith("FREQUENCY"):
            print("      %-60s %12s -> %12s" % (short(name), want, got))
m = re.findall(r"Timing errors:\s*\d+ \(setup\), \d+ \(hold\)", twr)
if m:
    print("    " + m[-1])
PY
}

summary_xilinx() {
	python3 - "$OUT/x32_spartan.mrp" "$OUT/x32_spartan.twr" <<'PY'
import re, sys
def read(p):
    try:
        return open(p, errors="replace").read()
    except OSError:
        return ""
mrp, twr = read(sys.argv[1]), read(sys.argv[2])

print("  Resources")
for label, pat in [
    ("Slice flip flops", r"Number of Slice Flip Flops:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("4 input LUTs", r"Total Number of 4 input LUTs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Occupied slices", r"Number of occupied Slices:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Block RAM", r"Number of RAMB16BWEs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Multipliers", r"Number of MULT18X18SIOs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("IO pins", r"Number of bonded IOBs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Global buffers", r"Number of BUFGMUXs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("DCMs", r"Number of DCMs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
]:
    m = re.search(pat, mrp)
    if m:
        print("    %-18s %6s of %6s  %3s%%" % (label, m.group(1).replace(",", ""), m.group(2).replace(",", ""), m.group(3)))

print("  Timing")
if not twr:
    print("    no timing report")
for block in re.split(r"\n(?=Timing constraint: )", twr)[1:]:
    head = " ".join(block.split("\n\n")[0].split())
    name = re.search(r"Timing constraint: (\S+)", head).group(1)
    m = re.search(r"PERIOD TIMEGRP \"[^\"]+\" (.*?) HIGH", head)
    want = m.group(1).strip() if m else ""
    err = re.search(r"(\d+) timing errors? detected", block)
    per = re.search(r"Minimum period is\s+([\d.]+)ns", block)
    if not per:
        continue
    period = float(per.group(1))
    flag = "  <-- %s errors" % err.group(1) if err and err.group(1) != "0" else ""
    print("      %-24s %-32s min. period %7.3f ns = %7.3f MHz%s" % (name, want, period, 1000.0 / period, flag))
m = re.search(r"Timing errors:\s*\d+[^\n]*", twr)
if m:
    print("    " + " ".join(m.group(0).split()))
if "All constraints were met" in twr:
    print("    All constraints were met.")
PY
}

report() {	# report <name> <title> <rc> <summary function>
	echo
	echo "== $2"
	if [ "$3" -eq 0 ]; then
		echo "  Build OK: build/$1.bit ($(stat -c %s "$OUT/$1.bit" 2>/dev/null) bytes)"
	else
		echo "  BUILD FAILED, see build/$1.log"
		grep -E '^ERROR|^@E|Error:' "$OUT/$1.log" 2>/dev/null | head -5 | sed 's/^/    /'
	fi
	[ -s "$OUT/$1.mrp" ] && "$4"
}

# ---------------------------------------------------------------------------
[ $# -eq 1 ] || usage
case "$1" in
	lattice) do_lattice=1; do_xilinx=0 ;;
	xilinx)  do_lattice=0; do_xilinx=1 ;;
	all|both) do_lattice=1; do_xilinx=1 ;;
	litex)   mkdir -p "$OUT"; generate_soc; exit 0 ;;
	*) usage ;;
esac

[ $do_lattice -eq 1 ] && check_lattice
[ $do_xilinx -eq 1 ] && check_xilinx

mkdir -p "$OUT"
generate_soc

if [ $do_xilinx -eq 1 ]; then
	# SSH asks this helper for the password (it is read from the environment, not stored)
	ISE_VM_PASSWORD="${ISE_VM_PASSWORD:-xilinx}"
	ASKPASS="$(mktemp)"
	trap 'rm -f "$ASKPASS"' EXIT
	printf '#!/bin/sh\nprintf "%%s\\n" "$ISE_VM_PASSWORD"\n' >"$ASKPASS"
	chmod 700 "$ASKPASS"
	export ISE_VM_PASSWORD
fi

rc_lattice=0
rc_xilinx=0
pid_lattice=""
pid_xilinx=""
if [ $do_lattice -eq 1 ]; then
	rm -f "$OUT"/x32_lattice.*
	echo "Lattice: building x32_lattice with Diamond (log: build/x32_lattice.log) ..."
	build_lattice & pid_lattice=$!
fi
if [ $do_xilinx -eq 1 ]; then
	rm -f "$OUT"/x32_spartan.*
	echo "Xilinx:  building x32_spartan in the VM $ISE_VM_HOST (log: build/x32_spartan.log) ..."
	build_xilinx & pid_xilinx=$!
fi
[ -n "$pid_lattice" ] && { wait "$pid_lattice"; rc_lattice=$?; }
[ -n "$pid_xilinx" ] && { wait "$pid_xilinx"; rc_xilinx=$?; }

[ $do_lattice -eq 1 ] && report x32_lattice "X32 / Lattice ECP5 LFE5U-25F" $rc_lattice summary_lattice
[ $do_xilinx -eq 1 ] && report x32_spartan "X32 / Xilinx Spartan-3A XC3S1400A" $rc_xilinx summary_xilinx

[ $rc_lattice -eq 0 ] && [ $rc_xilinx -eq 0 ]
