#!/usr/bin/env python3
"""Converts the code coverage in an .xcresult bundle to SonarQube's generic coverage format.

xccov_to_generic.py <result.xcresult> <repoRoot> > coverage.xml

Only source files under <repoRoot> are kept (not the tests), with paths relative to it. A line counts as covered when it ran at least
once; xccov's sub-line ranges are ignored (the generic format has no branch data from Swift).
"""
import os
import re
import subprocess
import sys
from xml.sax.saxutils import quoteattr

LINE = re.compile(r"^\s*(\d+): (\d+)")


def xccov(*args):
    return subprocess.run(["xcrun", "xccov", "view", "--archive", *args], check=True, capture_output=True, text=True).stdout


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    # Absolute paths of an existing bundle only: nothing that xccov could read as an option.
    result, root = os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])
    if not (result.endswith(".xcresult") and os.path.isdir(result) and os.path.isdir(root)):
        sys.exit(f"Not an .xcresult bundle and a folder: {sys.argv[1]} {sys.argv[2]}")
    out = ['<coverage version="1">']
    for path in xccov("--file-list", result).splitlines():
        real = os.path.realpath(path)
        if not real.startswith(root + os.sep) or f"{os.sep}Tests{os.sep}" in real:
            continue
        lines = [m for m in map(LINE.match, xccov("--file", path, result).splitlines()) if m]
        if not lines:
            continue
        out.append(f"  <file path={quoteattr(os.path.relpath(real, root))}>")
        out.extend(f'    <lineToCover lineNumber="{m[1]}" covered="{"true" if int(m[2]) > 0 else "false"}"/>' for m in lines)
        out.append("  </file>")
    out.append("</coverage>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
