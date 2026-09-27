#!/usr/bin/env python3
"""Build HotMac.app: compile the Swift sources and assemble a menu bar bundle.

SwiftPM does the compiling, so the app and the test suite share one definition
(Package.swift). This script only wraps the binary it produces: Info.plist, the
app icon, and an ad-hoc signature. Needs the Xcode Command Line Tools, which
provide swiftc and this interpreter.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
PRODUCT = "HotMac"
APP = ROOT / "HotMac.app"
BINARY = APP / "Contents" / "MacOS" / PRODUCT

# The icon source is a square PNG; the sizes below are the ten entries of a
# macOS .iconset, which iconutil compiles into Contents/Resources/AppIcon.icns.
ICON_SOURCE = ROOT / "AppIcon.png"
ICON_NAME = "AppIcon"
ICON_SIZES = (
    (16, "16x16"),
    (32, "16x16@2x"),
    (32, "32x32"),
    (64, "32x32@2x"),
    (128, "128x128"),
    (256, "128x128@2x"),
    (256, "256x256"),
    (512, "256x256@2x"),
    (512, "512x512"),
    (1024, "512x512@2x"),
)


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    """Run *command*, or exit with a readable message if it cannot start."""
    try:
        return subprocess.run(command, check=True, **kwargs)
    except FileNotFoundError:
        sys.exit(f"error: {command[0]} not found; install the Xcode Command Line Tools")
    except subprocess.CalledProcessError as error:
        sys.exit(f"error: {command[0]} failed with exit status {error.returncode}")


def run_quietly(command: list[str]) -> None:
    """Run *command* for its effect only, discarding its output."""
    run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def product_binary() -> pathlib.Path:
    """Compile the app and return the executable SwiftPM produced."""
    run(["swift", "build", "-c", "release", "--product", PRODUCT])
    bin_path = run(
        ["swift", "build", "-c", "release", "--show-bin-path"],
        capture_output=True,
        text=True,
    )
    return pathlib.Path(bin_path.stdout.strip()) / PRODUCT


def build_icon() -> None:
    """Render AppIcon.png into Contents/Resources/AppIcon.icns.

    Skipped, leaving the app on the generic icon, when the source image is
    absent; that keeps the build working for a checkout without the asset.
    """
    if not ICON_SOURCE.exists():
        return

    resources = APP / "Contents" / "Resources"
    iconset = resources / f"{ICON_NAME}.iconset"
    iconset.mkdir()
    for pixels, name in ICON_SIZES:
        run_quietly(
            [
                "sips",
                "-z",
                str(pixels),
                str(pixels),
                str(ICON_SOURCE),
                "--out",
                str(iconset / f"icon_{name}.png"),
            ]
        )
    run_quietly(
        [
            "iconutil",
            "-c",
            "icns",
            str(iconset),
            "-o",
            str(resources / f"{ICON_NAME}.icns"),
        ]
    )
    shutil.rmtree(iconset)


def main() -> int:
    binary = product_binary()

    shutil.rmtree(APP, ignore_errors=True)
    BINARY.parent.mkdir(parents=True, exist_ok=True)
    (APP / "Contents" / "Resources").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "Info.plist", APP / "Contents" / "Info.plist")
    # `copy`, not `copyfile`: the executable bit has to come with the binary.
    shutil.copy(binary, BINARY)
    build_icon()

    # Ad-hoc signing is a convenience for local runs, not a requirement.
    run_quietly(["codesign", "--force", "--sign", "-", str(APP)])

    print(f"Built {APP}")
    print(f'Run:  open "{APP}"')
    print("Stop: pkill -x HotMac")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
