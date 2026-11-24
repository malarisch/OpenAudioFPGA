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
# summaries (build_summary.py)
# ---------------------------------------------------------------------------
report() {	# report <name> <title> <rc> <family of build_summary.py>
	echo
	echo "== $2"
	if [ "$3" -eq 0 ]; then
		echo "  Build OK: build/$1.bit ($(stat -c %s "$OUT/$1.bit" 2>/dev/null) bytes)"
	else
		echo "  BUILD FAILED, see build/$1.log"
		grep -E '^ERROR|^@E|Error:' "$OUT/$1.log" 2>/dev/null | head -5 | sed 's/^/    /'
	fi
	[ -s "$OUT/$1.mrp" ] && python3 "$ROOT/build_summary.py" "$4" "$OUT/$1.mrp" "$OUT/$1.twr"
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

[ $do_lattice -eq 1 ] && report x32_lattice "X32 / Lattice ECP5 LFE5U-25F" $rc_lattice lattice
[ $do_xilinx -eq 1 ] && report x32_spartan "X32 / Xilinx Spartan-3A XC3S1400A" $rc_xilinx xilinx

[ $rc_lattice -eq 0 ] && [ $rc_xilinx -eq 0 ]
