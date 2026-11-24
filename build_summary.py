#!/usr/bin/env python3
"""Prints the resource utilisation and timing summary of an FPGA build.

    build_summary.py lattice <map report .mrp> <timing report .twr>    (Diamond)
    build_summary.py xilinx  <map report .mrp> <timing report .twr>    (ISE)

Called by build.sh after the builds; a missing report is treated as empty.
"""

import argparse
import re


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def print_resources(mrp, patterns):
    """patterns: (label, regex with the groups used, available, percent)"""
    print("  Resources")
    for label, pat in patterns:
        m = re.search(pat, mrp)
        if m:
            used, avail = (g.replace(",", "") for g in m.group(1, 2))
            print("    %-18s %6s of %6s  %3s%%" % (label, used, avail, m.group(3)))


MAX_PATHS = 5  # failing paths printed per constraint


def print_path(slack, src, dst, detail):
    """one path as two lines; the hierarchy both ends share is printed once"""
    cut = 0
    for i, (a, b) in enumerate(zip(src, dst)):
        if a != b:
            break
        if a == "/":
            cut = i + 1
    where = "  in " + src[:cut].rstrip("/") if cut else ""
    print("        %8.3f ns  %s -> %s  (%s)" % (slack, src[cut:], dst[cut:], detail))
    if where:
        print("                   %s" % where)


def print_paths(failing, worst):
    """failing: {constraint: (number of errors, [path, ...])}, a path being the
    arguments of print_path, worst slack first; worst: the tightest path that
    still meets its constraint (printed if nothing fails)"""
    for name, (errors, paths) in failing.items():
        print("      failing paths of %s (%d error(s)):" % (name, errors))
        for path in paths[:MAX_PATHS]:
            print_path(*path)
        if errors > min(len(paths), MAX_PATHS):
            print("        ... and %d more (%d listed in the timing report)" % (errors - min(len(paths), MAX_PATHS), len(paths)))
    if not failing and worst:
        print("      tightest path:")
        print_path(*worst)


# ---------------------------------------------------------------------------
# Lattice (Diamond)
# ---------------------------------------------------------------------------
LATTICE_RESOURCES = [
    ("Registers", r"Number of registers:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("Slices", r"Number of SLICEs:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("LUT4", r"Number of LUT4s:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("Block RAM (EBR)", r"Number of block RAMs:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("IO pins", r"Number of PIO sites used:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
    ("PLLs", r"Number of PLLs:\s+(\d+) out of\s+(\d+) \((\d+)%\)"),
]


def lattice_table(section):
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


def lattice_short(name):
    name = re.sub(r"\s+[\d.]+ (MHz|X)$", "", name)
    name = re.sub(r"^FREQUENCY\s*", "", name) or "(all other clocks)"
    return name if len(name) <= 60 else "..." + name[-57:]


def lattice_paths(report):
    """failing paths per preference and the tightest passing FREQUENCY path of one
    TRACE report (setup or hold); TRACE lists the worst paths of a preference first"""
    failing, worst = {}, None
    for block in re.split(r"\n={20,}\nPreference: ", report)[1:]:
        head, _, body = block.partition("\n-----")
        name = lattice_short(" ".join(head.split(";")[0].split()))
        err = re.search(r"(\d+) timing errors? detected", head)
        paths = []
        for m in re.finditer(
            r"^(Error|Passed): The following path (?:exceeds|meets) requirements by ([\d.]+)ns\s+"
            r"Logical Details:[^\n]*\s+"
            r"Source:\s+\S+\s+\S+\s+(\S+)\s+\(from (\S+) [+-]\)\s+"
            r"Destination:\s+\S+\s+.*?\s+(\S+)\s+\(to (\S+) [+-]\)\s+"
            r"Delay:\s+([\d.]+)ns[^\n]*?(\d+) logic levels",
            body, re.M,
        ):
            kind, slack, src, src_clk, dst, dst_clk, delay, levels = m.groups()
            clocks = lattice_short(src_clk) if src_clk == dst_clk else "%s -> %s" % (lattice_short(src_clk), lattice_short(dst_clk))
            detail = "delay %s ns, %s logic level(s), clock %s" % (delay, levels, clocks)
            slack = float(slack) if kind == "Passed" else -float(slack)
            paths.append((slack, src, dst, detail))
        bad = [p for p in paths if p[0] < 0]
        if bad:
            failing[name] = (int(err.group(1)) if err else len(bad), bad)
        elif paths and head.startswith("FREQUENCY") and (worst is None or paths[0][0] < worst[0]):
            worst = paths[0]
    return failing, worst


def summary_lattice(mrp, twr):
    print_resources(mrp, LATTICE_RESOURCES)
    m = re.search(r"^\s*MULT18X18D\s+(\d+)", mrp, re.M)
    if m:
        print("    %-18s %6s" % ("MULT18X18D", m.group(1)))

    print("  Timing")
    if not twr:
        print("    no timing report")
    # per analysis: the path details, then "Report Summary" with the table
    parts = twr.split("Report Summary")
    for title, report, section in zip(("setup", "hold"), parts, parts[1:]):
        section = section.split("Clock Domains Analysis")[0]
        rows = [r for r in lattice_table(section) if r[1] not in ("-", "")]
        bad = [r for r in rows if r[3]]
        print("    %s: %s" % (title, "%d preference(s) NOT met" % len(bad) if bad else "all preferences met"))
        for name, want, got, failed in rows:
            if failed:
                print("      %-60s %12s -> %12s  <-- not met" % (lattice_short(name), want, got))
            elif title == "setup" and name.startswith("FREQUENCY"):
                print("      %-60s %12s -> %12s" % (lattice_short(name), want, got))
        failing, worst = lattice_paths(report)
        print_paths(failing, worst if title == "setup" else None)
    m = re.findall(r"Timing errors:\s*\d+ \(setup\), \d+ \(hold\)", twr)
    if m:
        print("    " + m[-1])


# ---------------------------------------------------------------------------
# Xilinx (ISE)
# ---------------------------------------------------------------------------
XILINX_RESOURCES = [
    ("Slice flip flops", r"Number of Slice Flip Flops:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("4 input LUTs", r"Total Number of 4 input LUTs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Occupied slices", r"Number of occupied Slices:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Block RAM", r"Number of RAMB16BWEs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Multipliers", r"Number of MULT18X18SIOs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("IO pins", r"Number of bonded IOBs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("Global buffers", r"Number of BUFGMUXs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
    ("DCMs", r"Number of DCMs:\s+([\d,]+) out of\s+([\d,]+)\s+(\d+)%"),
]


def xilinx_paths(block):
    """paths (worst slack first) of one 'Timing constraint' block, per analysis"""
    paths = {"setup": [], "hold": []}
    for m in re.finditer(
        r"^Slack \((setup|hold) path\):\s+(-?[\d.]+)ns[^\n]*\n"
        r"\s+Source:\s+(\S+)[^\n]*\n"
        r"\s+Destination:\s+(\S+)[^\n]*\n"
        r"(?:\s+Requirement:[^\n]*\n)?"
        r"\s+Data Path Delay:\s+([\d.]+)ns \(Levels of Logic = (\d+)\)",
        block, re.M,
    ):
        kind, slack, src, dst, delay, levels = m.groups()
        detail = "delay %s ns, %s logic level(s)" % (delay, levels)
        paths[kind].append((float(slack), src, dst, detail))
    return paths


def summary_xilinx(mrp, twr):
    print_resources(mrp, XILINX_RESOURCES)
    failing, worst = {}, None

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
        for kind, paths in xilinx_paths(block).items():
            bad = [p for p in paths if p[0] < 0]
            if bad:
                count = re.search(r"(\d+) %s errors" % kind, block)
                failing["%s (%s)" % (name, kind)] = (int(count.group(1)) if count else len(bad), bad)
            elif paths and kind == "setup" and (worst is None or paths[0][0] < worst[0]):
                worst = paths[0]
        if not per:
            continue
        period = float(per.group(1))
        flag = "  <-- %s errors" % err.group(1) if err and err.group(1) != "0" else ""
        print("      %-24s %-32s min. period %7.3f ns = %7.3f MHz%s" % (name, want, period, 1000.0 / period, flag))
    print_paths(failing, worst)
    m = re.search(r"Timing errors:\s*\d+[^\n]*", twr)
    if m:
        print("    " + " ".join(m.group(0).split()))
    if "All constraints were met" in twr:
        print("    All constraints were met.")


SUMMARIES = {"lattice": summary_lattice, "xilinx": summary_xilinx}


def main():
    parser = argparse.ArgumentParser(description="Resource and timing summary of an FPGA build")
    parser.add_argument("family", choices=sorted(SUMMARIES))
    parser.add_argument("mrp", help="map report")
    parser.add_argument("twr", help="timing report")
    args = parser.parse_args()
    SUMMARIES[args.family](read(args.mrp), read(args.twr))


if __name__ == "__main__":
    main()
