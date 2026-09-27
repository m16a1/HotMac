#!/usr/bin/env python3
"""Build HotMac.app: compile the Swift sources and assemble a menu bar bundle.

Sources are discovered by walking Sources/ recursively, so a new file in any
subdirectory is picked up with no wiring. Needs the Xcode Command Line Tools,
which provide both swiftc and this interpreter.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SOURCES = ROOT / "Sources"
APP = ROOT / "HotMac.app"
BINARY = APP / "Contents" / "MacOS" / "HotMac"
FRAMEWORKS = ("SwiftUI", "AppKit", "Charts", "IOKit")


def run(command: list[str], *, quiet: bool = False) -> subprocess.CompletedProcess:
    """Run *command*, or exit with a readable message if it cannot start."""
    try:
        return subprocess.run(
            command,
            check=True,
            stdout=subprocess.DEVNULL if quiet else None,
            stderr=subprocess.DEVNULL if quiet else None,
        )
    except FileNotFoundError:
        sys.exit(f"error: {command[0]} not found; install the Xcode Command Line Tools")
    except subprocess.CalledProcessError as error:
        sys.exit(f"error: {command[0]} failed with exit status {error.returncode}")


def framework_flags() -> list[str]:
    return [flag for framework in FRAMEWORKS for flag in ("-framework", framework)]


def main() -> int:
    sources = sorted(SOURCES.rglob("*.swift"))
    if not sources:
        sys.exit(f"error: no Swift sources found under {SOURCES}")

    shutil.rmtree(APP, ignore_errors=True)
    BINARY.parent.mkdir(parents=True, exist_ok=True)
    (APP / "Contents" / "Resources").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "Info.plist", APP / "Contents" / "Info.plist")

    run(
        [
            "swiftc",
            "-O",
            "-parse-as-library",
            "-o",
            str(BINARY),
            *[str(source) for source in sources],
            *framework_flags(),
        ]
    )

    # Ad-hoc signing is a convenience for local runs, not a requirement.
    run(["codesign", "--force", "--sign", "-", str(APP)], quiet=True)

    print(f"Built {APP}")
    print(f'Run:  open "{APP}"')
    print("Stop: pkill -x HotMac")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
