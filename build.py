#!/usr/bin/env python3
"""Build HotMac.app: compile the Swift sources and assemble a menu bar bundle.

SwiftPM does the compiling, so the app and the test suite share one definition
(Package.swift). This script only wraps the binary it produces: Info.plist, the
app icon, and an ad-hoc signature. Needs the Xcode Command Line Tools, which
provide swiftc and this interpreter.

With --dist it also packages the bundle for a GitHub release, as
dist/HotMac-<version>.zip and a drag-to-Applications .dmg. The app is not
notarized, so a downloaded copy needs one Gatekeeper step to open; the README
explains that.
"""

from __future__ import annotations

import argparse
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

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


def app_version() -> str:
    """The version stamped into the bundle, so the archives match the About window."""
    with (ROOT / "Info.plist").open("rb") as handle:
        return plistlib.load(handle)["CFBundleShortVersionString"]


def dist_directory() -> pathlib.Path:
    """The gitignored directory the release archives are written to."""
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    return dist


def make_zip() -> pathlib.Path:
    """Zip the built bundle and return the archive path.

    `ditto` is used instead of `zip` because it preserves the bundle's metadata,
    which a plain zip drops and which the ad-hoc signature covers.
    """
    archive = dist_directory() / f"HotMac-{app_version()}.zip"
    archive.unlink(missing_ok=True)
    run_quietly(["ditto", "-c", "-k", "--keepParent", str(APP), str(archive)])
    return archive


def make_dmg() -> pathlib.Path:
    """Wrap the built bundle in a drag-to-Applications disk image.

    The staging folder holds the app and a symlink to /Applications, so the
    mounted image shows the usual drag target. hdiutil ships with macOS, so the
    image needs no third-party tool.
    """
    archive = dist_directory() / f"HotMac-{app_version()}.dmg"
    archive.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="hotmac-dmg-") as staging:
        stage = pathlib.Path(staging)
        run_quietly(["ditto", str(APP), str(stage / APP.name)])
        (stage / "Applications").symlink_to("/Applications")
        run_quietly(
            [
                "hdiutil",
                "create",
                "-volname", "HotMac",
                "-srcfolder",
                str(stage),
                "-ov",
                "-format",
                "UDZO",
                str(archive),
            ]
        )
    return archive


def make_dist() -> list[pathlib.Path]:
    """Build every release archive and return their paths."""
    return [make_zip(), make_dmg()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dist",
        action="store_true",
        help="also package the app for a release (dist/HotMac-<version>.zip and .dmg)",
    )
    args = parser.parse_args()

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
    if args.dist:
        for archive in make_dist():
            print(f"Release: {archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
