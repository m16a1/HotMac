#!/usr/bin/env python3
"""Run the HotMac logic tests.

No framework or package manager: the harness in Tests/main.swift is compiled
together with the Sources/Sensors/ layer and asserts directly. The UI layer is
deliberately not compiled here, because it needs Charts and a host app.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent
LOGIC_SOURCES = (
    ROOT / "Sources" / "Sensors" / "SMC.swift",
    ROOT / "Sources" / "Sensors" / "Sensors.swift",
    ROOT / "Sources" / "Sensors" / "TemperatureModel.swift",
)
FRAMEWORKS = ("SwiftUI", "AppKit", "IOKit")


def main() -> int:
    workdir = pathlib.Path(tempfile.mkdtemp(prefix="hotmac-tests-"))
    binary = workdir / "hotmac-tests"
    try:
        command = [
            "swiftc",
            "-O",
            "-DDEBUG",
            "-o",
            str(binary),
            str(ROOT / "Tests" / "main.swift"),
            *[str(source) for source in LOGIC_SOURCES],
            *[flag for framework in FRAMEWORKS for flag in ("-framework", framework)],
        ]
        try:
            subprocess.run(command, check=True)
        except FileNotFoundError:
            sys.exit("error: swiftc not found; install the Xcode Command Line Tools")
        return subprocess.run([str(binary)]).returncode
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
