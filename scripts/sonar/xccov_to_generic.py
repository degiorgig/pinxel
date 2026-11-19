#!/usr/bin/env python3
"""Converts the code coverage in an .xcresult bundle to SonarQube's generic coverage format.

xccov_to_generic.py > build/sonar-coverage.xml

It reads build/ci-package.xcresult, the bundle the CI package tests write. It takes no arguments, so nothing from the
command line reaches xcrun. Only source files under the repository are kept (not the tests), with paths relative to it. A line counts as covered when it ran at least
once; xccov's sub-line ranges are ignored (the generic format has no branch data from Swift).
"""
import os
import re
import subprocess
import sys
from xml.sax.saxutils import quoteattr

LINE = re.compile(r"^\s*(\d+): (\d+)")
ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RESULT = os.path.join(ROOT, "build", "ci-package.xcresult")


def xccov(*args):
    return subprocess.run(["xcrun", "xccov", "view", "--archive", *args], check=True, capture_output=True, text=True).stdout


def main():
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    result, root = RESULT, ROOT
    if not os.path.isdir(result):
        sys.exit(f"No result bundle at {result}: run the package tests with -resultBundlePath first.")
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
