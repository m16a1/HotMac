#!/usr/bin/env python3
"""Run the HotMac unit tests.

The suite is a Swift Testing target that SwiftPM builds as an executable, so a
plain `swift test` is not used; Package.swift explains why. The built binary is
run directly, which keeps `swift run`'s build noise out of the test output.

With --coverage the build is instrumented and an LLVM line/region report is
printed. Sources/UI/ is never compiled into the suite, and the IOKit and sysctl
calls in Sources/Sensors/System/ only work against real hardware, so that
directory is excluded from the report; the rest of the layer must stay at 100%.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent
TARGET = "SensorsTests"
COVERAGE_COMPILE_FLAGS = ("-profile-generate", "-profile-coverage-mapping")

# Sources/Sensors/System is the host boundary. Its behaviour depends on the
# machine (a kernel service, a sysctl), so even its failure branches cannot be
# produced in-process; the rest of the layer must reach 100%.
COVERAGE_EXCLUDE = "Sources/Sensors/System/"


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, check=True, **kwargs)
    except FileNotFoundError:
        sys.exit(f"error: {command[0]} not found; install the Xcode Command Line Tools")
    except subprocess.CalledProcessError as error:
        sys.exit(f"error: {command[0]} failed with exit status {error.returncode}")


def build(*swift_flags: str) -> pathlib.Path:
    """Build the suite with *swift_flags* and return its executable."""
    run(["swift", "build", *swift_flags])
    bin_path = run(["swift", "build", "--show-bin-path"], capture_output=True, text=True)
    return pathlib.Path(bin_path.stdout.strip()) / TARGET


def print_coverage(binary: pathlib.Path, profile: pathlib.Path, workdir: pathlib.Path) -> None:
    if not profile.exists():
        print("no coverage data was written", file=sys.stderr)
        return
    merged = workdir / "hotmac.profdata"
    # llvm-cov reads a merged profile; it rejects the raw one directly.
    run(["xcrun", "llvm-profdata", "merge", "-sparse", str(profile), "-o", str(merged)])
    run(
        [
            "xcrun",
            "llvm-cov",
            "report",
            str(binary),
            f"-instr-profile={merged}",
            "-sources",
            str(ROOT / "Sources"),
            f"-ignore-filename-regex={COVERAGE_EXCLUDE}",
        ]
    )
    print(f"note: {COVERAGE_EXCLUDE} is the host boundary and is excluded.")
    print("      Sources/UI is not compiled by this suite, so it is not measured at all.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--coverage",
        action="store_true",
        help="build with LLVM instrumentation and print a coverage report",
    )
    args = parser.parse_args()

    instrumentation = (
        [flag for name in COVERAGE_COMPILE_FLAGS for flag in ("-Xswiftc", name)]
        if args.coverage
        else []
    )
    binary = build(*instrumentation)

    workdir = pathlib.Path(tempfile.mkdtemp(prefix="hotmac-tests-"))
    try:
        profile = workdir / "hotmac.profraw"
        environment = dict(os.environ)
        if args.coverage:
            environment["LLVM_PROFILE_FILE"] = str(profile)

        status = subprocess.run([str(binary)], env=environment).returncode
        if args.coverage:
            print_coverage(binary, profile, workdir)
        return status
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
