# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow>=11"]
# ///
"""Package atlases as Codex v2 pets.

Each pet comes from the first build folder that has `<id>/spritesheet.png`:
by default the pixel-art atlases in `Build/pixel`, then the 3D renders in
`Build/render`. This script checks each atlas against the Codex v2 pet contract,
encodes it as lossless WebP, confirms that the WebP decodes to the same pixels,
and writes `Pets/<id>/spritesheet.webp` and `Pets/<id>/pet.json`.

    uv run Scripts/package.py [--build DIR]... [--pets Pets]
    uv run Scripts/package.py --check [--pets Pets]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

COLUMNS, ROWS = 8, 11
CELL_WIDTH, CELL_HEIGHT = 192, 208
# Frames per row: idle, running-right, running-left, waving, jumping,
# failed, waiting, running, review, and two rows of look directions.
FRAME_COUNTS = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
NEUTRAL_CELL = (0, 6)
MIN_USED_PIXELS = 50
MAX_WEBP_BYTES = 20 * 1024 * 1024


def check_atlas(image: Image.Image) -> list[str]:
    """Returns every way that `image` breaks the Codex v2 atlas contract."""
    errors = []
    if image.size != (COLUMNS * CELL_WIDTH, ROWS * CELL_HEIGHT):
        return [f"expected {COLUMNS * CELL_WIDTH}x{ROWS * CELL_HEIGHT}, got {image.width}x{image.height}"]
    if image.mode != "RGBA":
        return [f"expected RGBA, got {image.mode}"]
    alpha = image.getchannel("A")
    for row in range(ROWS):
        for column in range(COLUMNS):
            box = (column * CELL_WIDTH, row * CELL_HEIGHT, (column + 1) * CELL_WIDTH, (row + 1) * CELL_HEIGHT)
            visible = sum(alpha.crop(box).histogram()[1:])
            used = column < FRAME_COUNTS[row] or (row, column) == NEUTRAL_CELL
            if used and visible < MIN_USED_PIXELS:
                errors.append(f"row {row} column {column} is empty")
            if not used and visible:
                errors.append(f"row {row} column {column} should be transparent but has {visible} pixels")
            if used and visible > CELL_WIDTH * CELL_HEIGHT * 0.95:
                errors.append(f"row {row} column {column} is nearly opaque")
    red, green, blue, _ = image.split()
    color = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(lambda value: 255 if value else 0)
    transparent = alpha.point(lambda value: 255 if value == 0 else 0)
    residue = ImageChops.multiply(color, transparent).histogram()[255]
    if residue:
        errors.append(f"{residue} transparent pixels have color")
    return errors


MANIFEST_KEYS = ["id", "displayName", "description", "spriteVersionNumber", "spritesheetPath"]


def check_manifest(manifest: dict, path: Path) -> None:
    missing = [key for key in MANIFEST_KEYS if key not in manifest]
    if missing:
        raise SystemExit(f"{path}: missing {', '.join(missing)}")
    if manifest["spriteVersionNumber"] != 2 or manifest["spritesheetPath"] != "spritesheet.webp":
        raise SystemExit(f"{path}: expected spriteVersionNumber 2 and spritesheet.webp")


def load_atlas(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        return opened.convert("RGBA")


def package(source: Path, destination: Path) -> None:
    manifest = json.loads((source / "pet.json").read_text())
    check_manifest(manifest, source / "pet.json")
    atlas = load_atlas(source / "spritesheet.png")
    if errors := check_atlas(atlas):
        raise SystemExit(f"{source}: " + "; ".join(errors))

    destination.mkdir(parents=True, exist_ok=True)
    webp = destination / "spritesheet.webp"
    # `exact` keeps the color of transparent pixels at zero instead of letting
    # the encoder fill them in.
    atlas.save(webp, "WEBP", lossless=True, exact=True, quality=100, method=6)
    if load_atlas(webp).tobytes() != atlas.tobytes():
        raise SystemExit(f"{webp}: the WebP does not decode to the rendered pixels")
    if webp.stat().st_size > MAX_WEBP_BYTES:
        raise SystemExit(f"{webp}: larger than 20 MiB")
    manifest = {key: manifest[key] for key in MANIFEST_KEYS}
    (destination / "pet.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Packaged {manifest['displayName']} in {destination} ({webp.stat().st_size // 1024} KiB)")


def check(pet: Path) -> None:
    """Checks a packaged pet folder without changing it."""
    check_manifest(json.loads((pet / "pet.json").read_text()), pet / "pet.json")
    webp = pet / "spritesheet.webp"
    if webp.stat().st_size > MAX_WEBP_BYTES:
        raise SystemExit(f"{webp}: larger than 20 MiB")
    if errors := check_atlas(load_atlas(webp)):
        raise SystemExit(f"{webp}: " + "; ".join(errors))
    print(f"Checked {pet}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", type=Path, action="append",
                        help="a folder of <id>/spritesheet.png, in order of preference; repeatable")
    parser.add_argument("--pets", type=Path, default=Path("Pets"))
    parser.add_argument("--check", action="store_true", help="check the packaged pets instead of packaging")
    args = parser.parse_args()
    if args.check:
        pets = sorted(path.parent for path in args.pets.glob("*/pet.json"))
        if not pets:
            sys.exit(f"No pets in {args.pets}.")
        for pet in pets:
            check(pet)
        return
    builds = args.build or [Path("Build/pixel"), Path("Build/render")]
    sources: dict[str, Path] = {}
    for build in builds:
        for path in sorted(build.glob("*/spritesheet.png")):
            sources.setdefault(path.parent.name, path.parent)
    if not sources:
        sys.exit(f"No atlases in {', '.join(map(str, builds))}. Run `mise run render` first.")
    for name, source in sorted(sources.items()):
        package(source, args.pets / name)


if __name__ == "__main__":
    main()
