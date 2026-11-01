
#!/usr/bin/env python3

"""
One-time migration:
Use verified HW1 static tables in the Rubik C solver.

Run from the arch2026-progs repository root.
No build or network needed.
"""

from pathlib import Path
import re
import shutil

root = Path("src/rubik")
core = root / "solver_core.c"
asm = root / "minirubik_core.S"
out = root / "solver_tables.h"

if not core.exists() or not asm.exists():
    raise SystemExit(
        "Run from arch2026-progs root "
        "with core and asm present"
    )

if out.exists():
    raise SystemExit(
        f"{out} exists; aborting to avoid overwriting"
    )


def get_values(source, label, directive, expected):
    match = re.search(
        r"^" + re.escape(label) + r":\s*$",
        source,
        re.M
    )

    if not match:
        raise ValueError(f"Missing ASM label: {label}")

    block = source[match.end():]

    end = re.search(
        r"^(?:\.text|[A-Za-z_]\w*:)\s*$",
        block,
        re.M
    )

    if end:
        block = block[:end.start()]

    values = []

    for line in block.splitlines():
        line = line.split("#", 1)[0].strip()

        if line.startswith("." + directive + " "):
            values.extend(
                int(x.strip(), 0)
                for x in line.split(None, 1)[1].split(",")
            )

    if len(values) != expected:
        raise ValueError(
            f"{label} has {len(values)} values; "
            f"expected {expected}"
        )

    return values


# ----------------------------------------
# Step 1: Extract four ASM lookup tables
# ----------------------------------------

source = asm.read_text(encoding="utf-8")

parts = [
    "/* Generated from HW1 Assembly. Do not edit manually. */",
    "#ifndef RUBIK_SOLVER_TABLES_H",
    "#define RUBIK_SOLVER_TABLES_H"
]

tables = [
    (
        "perm_table",
        "permutation",
        "uint16_t",
        5040,
        15120,
        "half"
    ),
    (
        "orient_table",
        "orientation",
        "uint16_t",
        729,
        2187,
        "half"
    ),
    (
        "perm_dist",
        "permutation_distance",
        "uint8_t",
        None,
        5040,
        "byte"
    ),
    (
        "orient_dist",
        "orientation_distance",
        "uint8_t",
        None,
        729,
        "byte"
    )
]

for label, name, ctype, width, count, kind in tables:

    nums = get_values(
        source,
        label,
        kind,
        count
    )

    if width:
        parts.append(
            f"static const {ctype} {name}[3][{width}] = {{"
        )

        for face in range(3):
            parts.append("    {")

            row = nums[
                face * width:(face + 1) * width
            ]

            for i in range(0, width, 16):
                parts.append(
                    "        "
                    + ", ".join(map(str, row[i:i + 16]))
                    + ","
                )

            parts.append("    },")

    else:
        parts.append(
            f"static const {ctype} {name}[{count}] = {{"
        )

        for i in range(0, count, 16):
            parts.append(
                "    "
                + ", ".join(map(str, nums[i:i + 16]))
                + ","
            )

    parts.append("};")

parts.append("#endif")


# ----------------------------------------
# Step 2: Modify solver_core.c
# ----------------------------------------

text = core.read_text(encoding="utf-8")


def replace_region(before, after, replacement):
    global text

    i = text.find(before)
    j = text.find(after, i + len(before))

    if i < 0 or j < 0 or j <= i:
        raise ValueError(
            f"Cannot find unique region: {before[:55]!r}"
        )

    text = (
        text[:i]
        + replacement
        + text[j:]
    )


# Remove state expansion routines
# used only for runtime table construction.

replace_region(
    "/*@ requires \\valid(state); requires rank < STATES; assigns *state; */",
    "/*@ requires \\valid_read(state);",
    ""
)

# Replace dynamically allocated table declarations
# with the generated static lookup tables.

replace_region(
    "static uint16_t permutation[3][PERMUTATIONS];",
    "enum { MAX_SOLUTION = 11 };",
    '#include "solver_tables.h"\n'
)

# Remove the runtime BFS table-building functions.

replace_region(
    "/* BFS by level scans:",
    "static unsigned lower_bound(",
    ""
)

# Replace minirubik_init() with a no-op.
# The tables are now compiled into the program.

pattern = (
    r"static int tables_ready;\s*"
    r"int minirubik_init\(void\)\s*"
    r"\{\s*"
    r"if \(tables_ready\) return 1;\s*"
    r"if \(!build_tables\(\)\) return 0;\s*"
    r"tables_ready = 1;\s*"
    r"return 1;\s*"
    r"\}"
)

text, n = re.subn(
    pattern,
    "int minirubik_init(void)\n"
    "{\n"
    "    return 1;\n"
    "}",
    text
)

if n != 1:
    raise ValueError(
        "Could not identify the original minirubik_init()"
    )


# ----------------------------------------
# Step 3: Backup and write updated files
# ----------------------------------------

backup = Path(
    "mytests/solver_core.c.before_tables"
)

backup.parent.mkdir(
    parents=True,
    exist_ok=True
)

if backup.exists():
    raise SystemExit(
        f"{backup} already exists; aborting"
    )

shutil.copyfile(core, backup)

out.write_text(
    "\n".join(parts) + "\n",
    encoding="utf-8"
)

core.write_text(
    text,
    encoding="utf-8"
)

print(
    f"Generated {out} "
    "(40383 bytes of constant table data)"
)

print(
    f"Updated {core}; backup is {backup}"
)
