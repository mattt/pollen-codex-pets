# /// script
# requires-python = ">=3.12"
# dependencies = ["aseprite[image]>=0.1", "pillow>=11"]
# ///
"""Prepare rendered frames for PixelLab and finish the pixel art it returns.

    uv run Scripts/pixelart.py inputs --pet microduck [--raw Build/raw --out Build/transfer]
    uv run Scripts/pixelart.py collect --pet microduck --run DIR --labels LABEL...
        [--frames N...] [--mirror LABEL|-...]
    uv run Scripts/pixelart.py stage --pet microduck --run DIR...
    uv run Scripts/pixelart.py finish --pet microduck --run DIR
    uv run Scripts/pixelart.py assemble --pet microduck --frames DIR
    uv run Scripts/pixelart.py label --pet microduck
    uv run Scripts/pixelart.py export --pet microduck
    uv run Scripts/pixelart.py site-data --pet microduck --out FILE
    uv run Scripts/pixelart.py atlas --pet microduck [--out DIR]
    uv run Scripts/pixelart.py pet --pet microduck [--appearance graphite,feet=yellow] [--name NAME]
    uv run Scripts/pixelart.py outline IMAGE.png... --out DIR

The art lives in one file, `Art/<pet>/<pet>.aseprite`: indexed color on a palette
with one named ramp per part (such as `head-0`, `beak-1`, and `ring-3`), one 64 x 68 frame
per atlas cell in atlas order, a tag for each row, and the cell's label in each cel's user data.
Each pixel's part comes from the renderer's part mask in `Build/mask/<pet>/`, which
`mise run render` writes: where the pixel's color fits the part under it, it takes that part,
and where they disagree, the most common part nearby that its color allows. `Art/<pet>/provenance.json` records
where each frame came from and what the scripted cleanup changed.

`inputs` turns the raw renders in `Build/raw/<pet>/` (twice the atlas cell size,
from `render-pets --raw`) into 68 x 68 inputs for PixelLab's frame transfer,
in `Build/transfer/<pet>/`. Every raw render shares one scale and one floor line,
so the inputs do too.

`collect` copies the frames of an approved PixelLab run into `Build/art/<pet>/`
under their atlas labels, with outline A, and records where each one came from.
It crops 68 x 68 transfer frames back to 64 x 68.
It can save each frame mirrored under a second label.
`stage` and `finish` clean up collected frames with PixelLab.
`stage` takes `correct-pixelart` runs of frames from `Build/art/<pet>/`,
restores each frame's outline, and saves it under its label in `Build/tidy/<pet>/`
to quantize onto the sprite's palette, exported by `export`, with `reduce-colors`.
`finish` takes that `reduce-colors` run, restores the outline again,
keeps each frame on its floor line, repairs the feet, and writes the frames
into `Art/<pet>/<pet>.aseprite`. It remakes the mirrored frames from their sources.

`assemble` builds `Art/<pet>/<pet>.aseprite` from a folder of finished frames
under their atlas labels, with the same foot repair and palette mapping.
`label` gives every pixel of the sprite its part again, from the current part masks.
`export` writes every cel as a PNG under its label to `Build/art/<pet>/`,
for PixelLab and for review, and the palette to `Build/palette/<pet>.png`.
`atlas` scales the frames up 3x with hard edges, and packs them into
`Build/pixel/<pet>/spritesheet.png`, beside a copy of `Art/<pet>/pet.json`.
`pet` writes a pet in a buyer's colors to `Build/appearances/microduck-<hash>/`,
as the customizer site downloads it. `Art/<pet>/variants.json` lists the colors,
presets, and parts that the physical robot offers, and how the folder name is derived.

`outline` makes alpha hard, then redraws the outer ring of each sprite
in Pollen Pet's ink color, so that every frame has the same clean outline.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from collections import Counter

from aseprite import Color, ColorMode, Palette, Pixels, Sprite, UserData
from PIL import Image

SCALE = 3                 # Screen pixels per art pixel in the atlas.
CELL = (192, 208)         # Atlas cell, in screen pixels.
FRAME = (64, 68)          # Pixel-art frame: 3x this fills the cell.
TRANSFER = 68             # Transfer input side: square, and in PixelLab's 64-80 px tier.
INK = (0x10, 0x10, 0x18, 255)


def opaque_bounds(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox()


def transfer_input(raw: Image.Image) -> Image.Image:
    """Downscales a raw render into a 68 x 68 frame for PixelLab's frame transfer.

    The raw render is 6x a 64 x 69 frame. A box filter takes it to 64 x 69,
    dropping the empty top row gives the 64 x 68 frame,
    and the frame stands on the bottom of a transparent 68 x 68 canvas, centered.
    Transfer rejects 64 x 68, which straddles two of its size tiers.
    """
    width, height = FRAME
    small = raw.convert("RGBA").resize((width, height + 1), Image.Resampling.BOX).crop((0, 1, width, height + 1))
    canvas = Image.new("RGBA", (TRANSFER, TRANSFER))
    canvas.paste(small, ((TRANSFER - width) // 2, TRANSFER - height))
    return canvas


def command_inputs(args) -> None:
    raw = Path(args.raw) / args.pet
    paths = sorted(raw.glob("*.png"))
    if not paths:
        raise SystemExit(f"No raw frames in {raw}. Run `mise run render` first.")
    out = Path(args.out) / args.pet
    out.mkdir(parents=True, exist_ok=True)
    for path in paths:
        transfer_input(Image.open(path)).save(out / path.name)
    print(f"Wrote {len(paths)} transfer inputs, {TRANSFER} x {TRANSFER}, to {out}")


def outlined(image: Image.Image) -> Image.Image:
    """Hard alpha, then the outer ring of opaque pixels in ink."""
    image = image.convert("RGBA")
    width, height = image.size
    source = image.load()
    result = Image.new("RGBA", image.size)
    pixels = result.load()

    def solid(x: int, y: int) -> bool:
        return 0 <= x < width and 0 <= y < height and source[x, y][3] >= 128

    for y in range(height):
        for x in range(width):
            if not solid(x, y):
                continue
            edge = any(not solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            pixels[x, y] = INK if edge else source[x, y][:3] + (255,)
    return result


def unpadded(image: Image.Image, name: str) -> Image.Image:
    """Returns a 68 x 68 transfer frame to the 64 x 68 frame size.

    The input stood centered on the canvas's bottom edge, so the frame is
    the middle 64 columns. If PixelLab drew in the side padding, the 64 columns
    shift sideways just far enough to keep the robot whole; rows never move,
    so the floor line stays where the render put it.
    """
    image = image.convert("RGBA")
    if image.size == FRAME:
        return image
    if image.size != (TRANSFER, TRANSFER):
        raise SystemExit(f"{name} is {image.width} x {image.height}; expected {FRAME[0]} x {FRAME[1]} "
                         f"or {TRANSFER} x {TRANSFER}")
    width, height = FRAME
    left = (TRANSFER - width) // 2
    box = opaque_bounds(image)
    if box and (box[0] < left or box[2] > left + width):
        if box[2] - box[0] > width:
            raise SystemExit(f"{name} is {box[2] - box[0]} pixels wide and can't fit {width} columns")
        left = min(max(left, box[2] - width), box[0])
        print(f"  {name}: drawn in the padding; columns {left} to {left + width - 1} keep it whole")
    return image.crop((left, TRANSFER - height, left + width, TRANSFER))


def command_collect(args) -> None:
    """Copies the frames of one PixelLab run into Art/<pet>/frames/ under atlas labels."""
    run = Path(args.source)
    sources = sorted(run.glob("[0-9][0-9].png"))
    if args.frames is not None:
        if any(index >= len(sources) for index in args.frames):
            raise SystemExit(f"{run} has only {len(sources)} frames")
        chosen = args.frames
    else:
        chosen = list(range(len(sources)))
    if len(chosen) != len(args.labels):
        raise SystemExit(f"{len(chosen)} frames from {run} were chosen, but {len(args.labels)} labels were given")
    if args.mirror and len(args.mirror) != len(args.labels):
        raise SystemExit("Give one --mirror label for each frame, or none; use - to skip a frame.")
    out = staged(args.pet)
    out.mkdir(parents=True, exist_ok=True)
    record_path = provenance_path(args.pet)
    record = json.loads(record_path.read_text()) if record_path.exists() else {}
    job = json.loads((run / "run.json").read_text()).get("job") if (run / "run.json").exists() else None
    count = 0
    for position, (index, label) in enumerate(zip(chosen, args.labels)):
        frame = outlined(unpadded(Image.open(sources[index]), f"{run.name}/{sources[index].name}"))
        frame.save(out / f"{label}.png")
        record[label] = {"run": run.name, "job": job, "frame": index, "mirrored": False}
        count += 1
        mirrored = args.mirror[position] if args.mirror else "-"
        if mirrored != "-":
            frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT).save(out / f"{mirrored}.png")
            record[mirrored] = {"run": run.name, "job": job, "frame": index, "mirrored": True}
            count += 1
    record_path.write_text(json.dumps(dict(sorted(record.items())), indent=2) + "\n")
    print(f"Collected {count} frames from {run.name} into {out}")


def on_floor(image: Image.Image, before: Image.Image) -> Image.Image:
    """Moves a cleaned-up frame up or down so that its lowest pixel is where it was before.

    The render puts every pose on one floor line, and frame transfer keeps it.
    A cleanup pass that adds or drops a row at the feet would make the robot hop.
    """
    bounds, previous = opaque_bounds(image), opaque_bounds(before)
    if bounds is None or previous is None or bounds[3] == previous[3]:
        return image
    result = Image.new("RGBA", image.size)
    result.paste(image, (0, previous[3] - bounds[3]))
    return result


def command_stage(args) -> None:
    """Saves the frames of `correct-pixelart` runs under their labels, with the outline restored."""
    out = Path("Build/tidy") / args.pet
    out.mkdir(parents=True, exist_ok=True)
    sources_path = out / "sources.json"
    sources = json.loads(sources_path.read_text()) if sources_path.exists() else {}
    count = 0
    for run in map(Path, args.source):
        record = json.loads((run / "run.json").read_text())
        if record.get("endpoint") != "correct-pixelart":
            raise SystemExit(f"{run} is not a correct-pixelart run")
        for index, source in enumerate(record["images"]):
            label = Path(source).stem
            outlined(Image.open(run / f"{index:02d}.png")).save(out / f"{label}.png")
            sources[label] = run.name
            count += 1
    sources_path.write_text(json.dumps(dict(sorted(sources.items())), indent=2) + "\n")
    print(f"Staged {count} frames in {out}")


def command_finish(args) -> None:
    """Writes the frames of a `reduce-colors` run into Art/<pet>/<pet>.aseprite."""
    run = Path(args.source)
    record = json.loads((run / "run.json").read_text())
    if record.get("endpoint") != "reduce-colors":
        raise SystemExit(f"{run} is not a reduce-colors run")
    before = staged(args.pet)
    provenance = json.loads(provenance_path(args.pet).read_text())
    corrected = {}
    finished = {}
    for index, source in enumerate(record["images"]):
        source = Path(source)
        sources_path = source.parent / "sources.json"
        if sources_path.exists():
            corrected = json.loads(sources_path.read_text())
        finished[source.stem] = on_floor(outlined(Image.open(run / f"{index:02d}.png")),
                                         Image.open(before / f"{source.stem}.png"))
    # Remake each mirrored or copied frame from the finished frame with the same source.
    for label, entry in provenance.items():
        if label in finished or "run" not in entry:
            continue
        twin = next((other for other in list(finished) if not provenance[other].get("mirrored")
                     and provenance[other].get("run") == entry["run"]
                     and provenance[other].get("frame") == entry["frame"]), None)
        if twin:
            frame = finished[twin]
            finished[label] = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if entry["mirrored"] else frame
            corrected.setdefault(label, corrected.get(twin))
    sprite = Sprite.open(sprite_path(args.pet))
    for label, frame in finished.items():
        provenance[label]["corrected"] = corrected.get(label)
        provenance[label]["palette"] = run.name
        set_frame(sprite, label, frame, provenance[label], args.pet)
    write_mirrors(sprite)
    sprite.save(sprite_path(args.pet))
    provenance_path(args.pet).write_text(json.dumps(dict(sorted(provenance.items())), indent=2) + "\n")
    print(f"Finished {len(finished)} frames from {run.name} into {sprite_path(args.pet)}")


# The atlas, in Codex v2 order: nine animation rows, a neutral look frame, and 16 look directions.
ROWS = [("idle", 6), ("running-right", 8), ("running-left", 8), ("waving", 4), ("jumping", 5),
        ("failed", 8), ("waiting", 6), ("running", 6), ("review", 6)]
LOOKS = [f"look-{index * 22.5:05.1f}" for index in range(16)]


def atlas_cells() -> list[tuple[str, int, int]]:
    cells = [(f"{state}-{frame}", row, frame) for row, (state, count) in enumerate(ROWS) for frame in range(count)]
    cells.append(("neutral", 0, 6))
    cells += [(label, len(ROWS) + index // 8, index % 8) for index, label in enumerate(LOOKS)]
    return cells


# Where the art and its records live.


def sprite_path(pet: str) -> Path:
    return Path("Art") / pet / f"{pet}.aseprite"


def provenance_path(pet: str) -> Path:
    return Path("Art") / pet / "provenance.json"


def staged(pet: str) -> Path:
    """Frames on their way through PixelLab: collected runs, and exports of the sprite."""
    return Path("Build/art") / pet


# The source colors, as ramps by material, lightest first.
# PixelLab's runs are quantized onto these; the sprite's palette repeats them for each part.
PALETTE: list[tuple[str, tuple[int, int, int]]] = [
    ("ink", (0x10, 0x10, 0x18)),        # The outline.
    ("servo-0", (0x03, 0x08, 0x07)),    # Servos, neck, shins, and the face: darkest.
    ("servo-1", (0x1F, 0x26, 0x27)),
    ("servo-2", (0x37, 0x3D, 0x3A)),
    ("servo-3", (0x4B, 0x53, 0x4F)),
    ("servo-4", (0x74, 0x78, 0x6E)),    # Glints on the servos and the lens.
    ("shell-0", (0xF9, 0xF3, 0xE1)),    # Head, body, and thigh shells: highlight.
    ("shell-1", (0xE7, 0xE6, 0xD5)),    # Sheen, also on the white hip brackets.
    ("shell-2", (0xE0, 0xDA, 0xBA)),    # Base.
    ("shell-3", (0xC8, 0xC3, 0xA8)),    # Shadow.
    ("shell-4", (0xA4, 0xB7, 0xA4)),    # Cool shadow, on the brackets and the shells' undersides.
    ("shell-5", (0x9E, 0x9E, 0x8A)),    # Deep shadow.
    ("accent-0", (0xE5, 0xB1, 0x53)),   # Beak, feet, and lens ring: light.
    ("accent-1", (0xCD, 0x80, 0x3C)),
    ("accent-2", (0xAF, 0x65, 0x2C)),   # Shadow.
]
RGB = dict(PALETTE)
# Colors from PixelLab's palettes that merge into one named color: near-black duplicates.
MERGED = {(0x00, 0x00, 0x00): "servo-0", (0x00, 0x02, 0x05): "servo-0", (0x01, 0x06, 0x02): "servo-0",
          (0x01, 0x07, 0x06): "servo-0", (0x08, 0x0E, 0x0D): "servo-0"}
ACCENT = ["accent-0", "accent-1", "accent-2"]
DARK = ["servo-0", "servo-1", "servo-2", "servo-3"]
# Colors that don't belong on a foot: the teal pads' leftovers, shell shades, and glints.
PALE = ["shell-0", "shell-1", "shell-2", "shell-3", "shell-4", "shell-5", "servo-4"]
SIDES = ((1, 0), (-1, 0), (0, 1), (0, -1))


def nearest(rgb: tuple[int, int, int]) -> str:
    if rgb in MERGED:
        return MERGED[rgb]
    return min(PALETTE, key=lambda entry: sum((a - b) ** 2 for a, b in zip(entry[1], rgb)))[0]


def named(image: Image.Image) -> list[list[str | None]]:
    """Each pixel's palette name, or None where it's clear."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    cache: dict[tuple[int, int, int], str] = {}
    grid = []
    for y in range(height):
        row = []
        for x in range(width):
            r, g, b, a = pixels[x, y]
            row.append(cache.setdefault((r, g, b), nearest((r, g, b))) if a >= 128 else None)
        grid.append(row)
    return grid


def feet(grid: list[list[str | None]]) -> set[tuple[int, int]]:
    """The feet: runs of orange in the lower 30 percent of the figure that are wider than tall.

    The beak's edge, seen face-down, is also low but is a tall bar, and the lens ring is high.
    """
    height, width = len(grid), len(grid[0])
    rows = [y for y in range(height) if any(grid[y])]
    if not rows:
        return set()
    top, bottom = rows[0], rows[-1] + 1
    seen: set[tuple[int, int]] = set()
    found: set[tuple[int, int]] = set()
    for y in range(height):
        for x in range(width):
            if (x, y) in seen or grid[y][x] not in ACCENT:
                continue
            component, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                component.append((cx, cy))
                for dx, dy in SIDES:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < width and 0 <= ny < height and (nx, ny) not in seen and grid[ny][nx] in ACCENT:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            xs, ys = [p[0] for p in component], [p[1] for p in component]
            if (len(component) >= 8 and max(ys) >= top + 0.7 * (bottom - top)
                    and max(xs) - min(xs) + 1 >= 0.8 * (max(ys) - min(ys) + 1)):
                found.update(component)
    return found


def repair_feet(grid: list[list[str | None]]) -> int:
    """Repairs the feet in place and returns how many pixels changed.

    Near each foot, until nothing changes:
    a pale pixel whose neighbors are all orange, ink, or pale becomes orange,
    in shadow where it sits on the outline, else the most common orange beside it;
    an ink or dark pixel with three orange neighbors becomes that orange;
    and ink doubled inside the outline, between orange and the outer edge, becomes orange shadow.
    The outer ring of every frame stays ink.
    """
    height, width = len(grid), len(grid[0])

    def get(x: int, y: int) -> str | None:
        return grid[y][x] if 0 <= x < width and 0 <= y < height else None

    def edge(x: int, y: int) -> bool:
        return any(get(x + dx, y + dy) is None for dx, dy in SIDES)

    near = {(x + dx, y + dy) for x, y in feet(grid) for dx in range(-2, 3) for dy in range(-2, 3)}
    changed: set[tuple[int, int]] = set()
    while True:
        updates = {}
        for x, y in sorted(near):
            name = get(x, y)
            if name is None or edge(x, y):
                continue
            sides = [get(x + dx, y + dy) for dx, dy in SIDES]
            orange = [n for n in sides if n in ACCENT]
            most = Counter(orange).most_common(1)[0][0] if orange else None
            if name in PALE and orange and all(n in ACCENT or n == "ink" or n in PALE for n in sides):
                updates[(x, y)] = "accent-2" if get(x, y + 1) == "ink" else most
            elif (name == "ink" or name in DARK) and len(orange) >= 3:
                updates[(x, y)] = most
            elif name == "ink":
                for dx, dy in SIDES:
                    across = (get(x + dy, y + dx), get(x - dy, y - dx))
                    if (get(x + dx, y + dy) == "ink" and edge(x + dx, y + dy) and get(x - dx, y - dy) in ACCENT
                            and all(n in ACCENT or n == "ink" for n in across) and any(n in ACCENT for n in across)):
                        updates[(x, y)] = "accent-2"
                        break
        updates = {point: name for point, name in updates.items() if get(*point) != name}
        if not updates:
            return len(changed)
        for (x, y), name in updates.items():
            grid[y][x] = name
            changed.add((x, y))


# The parts that a buyer could color, as the renderer's part mask names them,
# with the materials each is drawn in. The sprite's palette has one ramp per part,
# with every color of its materials, so a variant can recolor one part and leave the others.
# The lens ring is dark on the model, and PixelLab drew it dark in some frames and orange in others.
PARTS: list[tuple[str, list[str]]] = [
    ("head", ["shell"]), ("beak", ["accent"]), ("mouth", ["shell"]), ("ring", ["accent", "servo"]),
    ("lens", ["servo"]), ("face", ["servo"]), ("body", ["shell"]), ("thighs", ["shell"]),
    ("brackets", ["shell"]), ("feet", ["accent"]), ("ankles", ["accent"]), ("soles", ["accent"]),
    ("servos", ["servo"]),
]
MATERIALS = dict(PARTS)
# How the customizer names each part.
PART_LABELS = {
    "head": "Head shell", "beak": "Beak", "mouth": "Inside of the mouth", "ring": "Lens ring",
    "lens": "Lens", "face": "Face plate", "body": "Body shell", "thighs": "Thigh shells",
    "brackets": "Hip brackets", "feet": "Feet", "ankles": "Ankles", "soles": "Soles", "servos": "Servos and neck",
}
# Each material's colors, lightest first, and the one that a variant's base color replaces.
RAMPS = {material: [name for name, _ in PALETTE if name.startswith(material + "-")]
         for material in ("shell", "accent", "servo")}
BASE = {"shell": "shell-2", "accent": "accent-1", "servo": "servo-2"}
# Where neither the mask nor the neighborhood names a part for a color, its material decides.
FALLBACK = {"shell": "body", "accent": "beak", "servo": "servos"}


# Parts whose edge pixels, where they meet the ink outline or a dark part, have their own ramp,
# such as head-rim-0, with the same colors. A dark color can lighten that rim, so the part
# keeps its outline against the ink, the face, and the servos.
RIM_PARTS = ("head", "body", "beak")


def part_palette() -> list[tuple[str, tuple[int, int, int], str]]:
    """The sprite's palette after transparent: each entry's name, color, and source color's name."""
    entries = [("ink", RGB["ink"], "ink")]
    for part, materials in PARTS:
        sources = [source for material in materials for source in RAMPS[material]]
        for ramp in [part] + ([f"{part}-rim"] if part in RIM_PARTS else []):
            for index, source in enumerate(sources):
                entries.append((f"{ramp}-{index}", RGB[source], source))
    return entries


PART_INDEX = {("ink", "ink"): 1}
PART_INDEX.update({(name.rsplit("-", 1)[0], source): index + 1
                   for index, (name, _, source) in enumerate(part_palette()) if name != "ink"})


def material_of(name: str) -> str:
    return name.split("-")[0]


def indexed(grid: list[list[str | None]], parts: list[list[str | None]]) -> Pixels:
    data = bytes(0 if name is None else PART_INDEX[("ink", "ink") if name == "ink" else (part, name)]
                 for row, part_row in zip(grid, parts) for name, part in zip(row, part_row))
    return Pixels(len(grid[0]), len(grid), data, ColorMode.INDEXED)


def palette() -> Palette:
    colors = [Color(0, 0, 0, 0, name="transparent")]
    colors += [Color(*rgb, name=name) for name, rgb, _ in part_palette()]
    return Palette(colors)


def mask_source(label: str) -> tuple[str, bool]:
    """The rendered mask that a frame's art came from, and whether to mirror it.

    The walk to the left mirrors the walk to the right, and the looks past 180 degrees
    mirror the looks before it, as the art does.
    """
    if label.startswith("running-left-"):
        return label.replace("running-left-", "running-right-"), True
    if label.startswith("look-") and float(label[5:]) > 180:
        return f"look-{360 - float(label[5:]):05.1f}", True
    return label, False


def part_mask(pet: str, label: str) -> list[list[str | None]]:
    """The part under each art pixel: the renderer's mask, downscaled and cropped as the transfer
    inputs are, taking the most common part in each pixel's block."""
    directory = Path("Build/mask") / pet
    manifest = directory / "parts.json"
    if not manifest.exists():
        raise SystemExit(f"No part masks in {directory}. Run `mise run render` first.")
    ids = [(entry["name"], tuple(int(entry["color"][i:i + 2], 16) for i in (1, 3, 5)))
           for entry in json.loads(manifest.read_text())["parts"]]
    source, mirrored = mask_source(label)
    raw = Image.open(directory / f"{source}.png").convert("RGBA")
    width, height = raw.size
    pixels = raw.load()
    cache: dict[tuple[int, int, int], str] = {}

    def part(x: int, y: int) -> str | None:
        r, g, b, a = pixels[x, y]
        if a < 128:
            return None
        if (r, g, b) not in cache:
            # The renderer's flat colors shift a little in color management; snap to the nearest.
            cache[(r, g, b)] = min(ids, key=lambda entry: sum((p - q) ** 2 for p, q in zip(entry[1], (r, g, b))))[0]
        return cache[(r, g, b)]

    # transfer_input scales to FRAME[0] x (FRAME[1] + 1) and drops the top row.
    columns, rows = FRAME[0], FRAME[1] + 1
    grid = []
    for row in range(1, rows):
        y0, y1 = row * height // rows, (row + 1) * height // rows
        line = []
        for column in range(columns):
            x0, x1 = column * width // columns, (column + 1) * width // columns
            votes = Counter(p for y in range(y0, y1) for x in range(x0, x1) if (p := part(x, y)))
            line.append(votes.most_common(1)[0][0] if votes else None)
        grid.append(line[::-1] if mirrored else line)
    return grid


def label_parts(grid: list[list[str | None]], mask: list[list[str | None]]) -> tuple[list[list[str | None]], Counter]:
    """Gives each art pixel a part, and returns the parts and where the mask and the art disagree.

    A pixel whose color's material fits the part under it in the mask takes that part.
    Where they disagree, as where PixelLab's drawing strays from the render, the pixel takes
    the most common part nearby that its material allows. The outline stays ink.
    """
    height, width = len(grid), len(grid[0])
    parts: list[list[str | None]] = [[None] * width for _ in range(height)]
    disagreements: Counter = Counter()
    for y in range(height):
        for x in range(width):
            name = grid[y][x]
            if name is None or name == "ink":
                parts[y][x] = name
                continue
            material = material_of(name)
            here = mask[y][x]
            if here is not None and material in MATERIALS[here]:
                # The art's color fits the part under it.
                parts[y][x] = here
                continue
            if here is None:
                disagreements["art outside the render's outline"] += 1
            else:
                disagreements[f"{material} art on the {here} mask"] += 1
            for radius in (2, 4, 8):
                votes = Counter()
                for dy in range(-radius, radius + 1):
                    for dx in range(-radius, radius + 1):
                        if 0 <= y + dy < height and 0 <= x + dx < width:
                            candidate = mask[y + dy][x + dx]
                            if candidate and material in MATERIALS[candidate]:
                                # Nearer pixels count more, so ties go to the nearest part.
                                votes[candidate] += 1 + 1 / (abs(dx) + abs(dy))
                if votes:
                    parts[y][x] = votes.most_common(1)[0][0]
                    if radius > 2:
                        disagreements["parts found beyond 2 pixels"] += 1
                    break
            else:
                parts[y][x] = FALLBACK[material]
                disagreements["no part in reach; the material decided"] += 1
    return parts, disagreements


# Frame durations: the Codex contract's, for playback in Aseprite.
DURATIONS = {"idle": [280, 110, 110, 140, 140, 320], "running-right": [120] * 7 + [220],
             "running-left": [120] * 7 + [220], "waving": [140, 140, 140, 280], "jumping": [140] * 4 + [280],
             "failed": [140] * 7 + [240], "waiting": [150] * 5 + [260], "running": [120] * 5 + [220],
             "review": [150] * 5 + [280]}


def sprite_cells() -> list[tuple[str, int]]:
    """Every atlas cell's label and duration, in atlas order: row by row, left to right."""
    cells = []
    for label, row, column in sorted(atlas_cells(), key=lambda cell: (cell[1], cell[2])):
        state = label.rsplit("-", 1)[0]
        cells.append((label, DURATIONS[state][column] if state in DURATIONS else 100))
    return cells


def mark_rims(grid: list[list[str | None]], parts: list[list[str | None]]) -> None:
    """Moves each rim part's pixels that touch ink or a dark part onto the part's rim ramp."""
    height, width = len(grid), len(grid[0])
    for y in range(height):
        for x in range(width):
            if parts[y][x] not in RIM_PARTS:
                continue
            for dx, dy in SIDES:
                if 0 <= x + dx < width and 0 <= y + dy < height:
                    neighbor = grid[y + dy][x + dx]
                    if neighbor == "ink" or (neighbor and material_of(neighbor) == "servo"):
                        parts[y][x] = f"{parts[y][x]}-rim"
                        break


def write_cel(sprite: Sprite, label: str, grid: list[list[str | None]], pet: str) -> Counter:
    """Writes one frame's colors into its cel, each on its part's ramp, and returns the disagreements."""
    parts, disagreements = label_parts(grid, part_mask(pet, label))
    mark_rims(grid, parts)
    labels = [label for label, _ in sprite_cells()]
    cel = sprite.frames[labels.index(label)].set_cel(0, indexed(grid, parts))
    cel.user_data = UserData(text=label)
    return disagreements


def write_mirrors(sprite: Sprite) -> None:
    """Makes every mirrored frame its twin's cel, flipped, so the two can't drift apart.

    The foot repair and the part vote break ties in a fixed order that isn't symmetric,
    so running them on a mirrored frame can differ from its twin by a pixel.
    """
    labels = [label for label, _ in sprite_cells()]
    width, height = FRAME
    for label in labels:
        twin, mirrored = mask_source(label)
        if not mirrored:
            continue
        data = sprite.frames[labels.index(twin)].cel(0).pixels.data
        flipped = bytes(data[y * width + width - 1 - x] for y in range(height) for x in range(width))
        cel = sprite.frames[labels.index(label)].set_cel(0, Pixels(width, height, flipped, ColorMode.INDEXED))
        cel.user_data = UserData(text=label)


def set_frame(sprite: Sprite, label: str, image: Image.Image, record: dict, pet: str) -> Counter:
    """Replaces one frame's cel with a finished image, after repairing its feet."""
    grid = named(image)
    repaired = repair_feet(grid)
    record.pop("feet", None)
    if repaired:
        record["feet"] = f"{repaired} pixels repaired by pixelart.py's foot rules"
    return write_cel(sprite, label, grid, pet)


def command_label(args) -> None:
    """Gives every pixel of the sprite its part again, from the renderer's current part masks."""
    sprite = Sprite.open(sprite_path(args.pet))
    images = frame_images(sprite)
    sprite.palette = palette()
    total: Counter = Counter()
    for label, _ in sprite_cells():
        total += write_cel(sprite, label, named(images[label]), args.pet)
    write_mirrors(sprite)
    sprite.save(sprite_path(args.pet))
    print(f"Labeled {len(images)} frames in {sprite_path(args.pet)} with {len(PARTS)} parts")
    for kind, count in total.most_common():
        print(f"  {count:5d} pixels: {kind}")


def command_assemble(args) -> None:
    """Builds Art/<pet>/<pet>.aseprite from a folder of finished frames."""
    folder = Path(args.frames)
    cells = sprite_cells()
    missing = [label for label, _ in cells if not (folder / f"{label}.png").exists()]
    if missing:
        raise SystemExit(f"Missing frames in {folder}: {', '.join(missing)}")
    provenance = json.loads(provenance_path(args.pet).read_text())
    sprite = Sprite(*FRAME, ColorMode.INDEXED, empty=True)
    sprite.add_layer(args.pet.capitalize())
    sprite.palette = palette()
    sprite.transparent_index = 0
    for label, duration in cells:
        frame = sprite.add_frame(duration)
        frame.set_cel(0, Pixels.blank(*FRAME, ColorMode.INDEXED))
    for label, _ in cells:
        set_frame(sprite, label, Image.open(folder / f"{label}.png"), provenance.setdefault(label, {}), args.pet)
    write_mirrors(sprite)
    # One tag per row, then the neutral frame and the 16 look directions.
    labels = [label for label, _ in cells]
    for state, count in ROWS:
        start = labels.index(f"{state}-0")
        sprite.add_tag(state, start, start + count - 1)
    sprite.add_tag("neutral", labels.index("neutral"), labels.index("neutral"))
    sprite.add_tag("look", labels.index(LOOKS[0]), labels.index(LOOKS[-1]))
    sprite.save(sprite_path(args.pet))
    provenance_path(args.pet).write_text(json.dumps(dict(sorted(provenance.items())), indent=2) + "\n")
    repaired = sum(1 for label in labels if "feet" in provenance[label])
    print(f"Wrote {sprite_path(args.pet)}: {len(cells)} frames, {len(part_palette())} colors, "
          f"feet repaired in {repaired} frames")


def frame_images(sprite: Sprite) -> dict[str, Image.Image]:
    """Each frame, flattened, under the label in its cel's user data."""
    images = {}
    for index, frame in enumerate(sprite.frames):
        cel = frame.cel(0)
        label = cel.user_data.text if cel and cel.user_data else None
        if label:
            images[label] = sprite.image(index)
    return images


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def derived_ramp(material: str, base: tuple[int, int, int]) -> list[tuple[int, int, int]]:
    """A material's ramp moved onto a new base color.

    Each shade keeps its saturation and brightness relative to the default base,
    and takes the new base's hue, so a shell keeps its highlight and shadows in any color.
    """
    import colorsys
    old = colorsys.rgb_to_hsv(*(c / 255 for c in RGB[BASE[material]]))
    new = colorsys.rgb_to_hsv(*(c / 255 for c in base))
    ramp = []
    for name in RAMPS[material]:
        h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in RGB[name]))
        saturation = min(1.0, new[1] * s / max(old[1], 0.02))
        value = min(1.0, new[2] * v / max(old[2], 0.02))
        ramp.append(tuple(round(c * 255) for c in colorsys.hsv_to_rgb(new[0], saturation, value)))
    return ramp


# The paint color that the renderer gives each recolorable material, and so the color
# that the art's base shade stands for. A buyer's color maps to an art base color by
# the same change in saturation and brightness, so it looks as lit as the default does.
PAINT = {"shell": (0xEE, 0xE6, 0xD2), "accent": (0xF1, 0x8B, 0x42)}


def art_base(paint: tuple[int, int, int], material: str) -> tuple[int, int, int]:
    """The art base color for a paint color on a material."""
    import colorsys
    painted = colorsys.rgb_to_hsv(*(c / 255 for c in PAINT[material]))
    drawn = colorsys.rgb_to_hsv(*(c / 255 for c in RGB[BASE[material]]))
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in paint))
    saturation = min(1.0, s * drawn[1] / max(painted[1], 0.02))
    value = min(1.0, v * drawn[2] / max(painted[2], 0.02))
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, saturation, value))


def appearance_spec(pet: str) -> dict:
    return json.loads((Path("Art") / pet / "variants.json").read_text())


def default_appearance(spec: dict) -> dict[str, str]:
    return preset_appearance(spec, spec["default"])


def preset_appearance(spec: dict, preset: str) -> dict[str, str]:
    """A factory preset: the head and body in the preset's color, the beak and feet in the accent."""
    if preset not in spec["presets"]:
        raise SystemExit(f"{preset} isn't a preset; the presets are {', '.join(spec['presets'])}")
    return {"head": preset, "body": preset, "beak": spec["presetAccent"], "feet": spec["presetAccent"]}


def parse_appearance(spec: dict, text: str) -> dict[str, str]:
    """An appearance from a preset and part choices, such as `graphite,feet=yellow`.

    It starts from the default preset, then applies each item in order.
    """
    appearance = default_appearance(spec)
    colors = {color["id"] for color in spec["colors"]}
    for item in filter(None, (item.strip() for item in text.split(","))):
        if "=" not in item:
            appearance = preset_appearance(spec, item)
            continue
        part, color = (value.strip() for value in item.split("=", 1))
        if part not in appearance:
            raise SystemExit(f"{part} isn't a part; the parts are {', '.join(appearance)}")
        if color not in colors:
            raise SystemExit(f"{color} isn't a color; the colors are {', '.join(sorted(colors))}")
        appearance[part] = color
    return appearance


def appearance_folder(appearance: dict[str, str]) -> str:
    """The pet's folder name: the same appearance always gives the same name.

    The encoding is versioned, so a later change to the options can't reuse a name.
    """
    import hashlib
    encoding = "microduck-appearance/1 " + " ".join(f"{part}={appearance[part]}" for part in ("head", "body", "beak", "feet"))
    return "microduck-" + hashlib.sha256(encoding.encode()).hexdigest()[:7]


def appearance_colors(spec: dict, part: str, color: str) -> dict[str, tuple[int, int, int]]:
    """The palette entries that one buyer part's color changes, or none for its default color."""
    if default_appearance(spec)[part] == color:
        return {}
    import colorsys
    definition = next(entry for entry in spec["colors"] if entry["id"] == color)
    paint = hex_rgb(definition["rgb"])
    # A dark color lightens its rim by this much HSV brightness, so the part keeps its outline.
    lift = definition.get("rim", 0.0)
    sprite_parts = next(entry["spriteParts"] for entry in spec["parts"] if entry["id"] == part)
    colors = {}
    for sprite_part in sprite_parts:
        ramps = {material: derived_ramp(material, art_base(paint, material)) for material in MATERIALS[sprite_part]}
        for entry, _, source in part_palette():
            ramp = entry.rsplit("-", 1)[0]
            if ramp not in (sprite_part, f"{sprite_part}-rim"):
                continue
            material = material_of(source)
            rgb = ramps[material][RAMPS[material].index(source)]
            if ramp.endswith("-rim") and lift:
                h, sat, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
                rgb = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, sat, min(1.0, v + lift)))
            colors[entry] = rgb
    return colors


def apply_appearance(sprite: Sprite, spec: dict, appearance: dict[str, str]) -> None:
    colors = {}
    for part, color in appearance.items():
        colors.update(appearance_colors(spec, part, color))
    for entry in sprite.palette.colors:
        if entry.name in colors:
            entry.r, entry.g, entry.b = colors[entry.name]


def run_lengths(data: bytes) -> bytes:
    """Pairs of (count, value), each count from 1 to 255."""
    out = bytearray()
    index = 0
    while index < len(data):
        value, count = data[index], 1
        while index + count < len(data) and data[index + count] == value and count < 255:
            count += 1
        out += bytes((count, value))
        index += count
    return bytes(out)


def command_site_data(args) -> None:
    """Writes the customizer's art data from the sprite, so the site and the packaged pet agree."""
    import base64
    import hashlib
    sprite = Sprite.open(sprite_path(args.pet))
    labels = [label for label, _ in sprite_cells()]
    cells = {label: (row, column) for label, row, column in atlas_cells()}
    frames = []
    for (label, duration), frame in zip(sprite_cells(), sprite.frames):
        cel = frame.cel(0)
        if not cel or not cel.user_data or cel.user_data.text != label:
            raise SystemExit(f"Frame {labels.index(label)} of the sprite isn't {label}")
        row, column = cells[label]
        frames.append({"label": label, "row": row, "column": column, "duration": duration,
                       "pixels": base64.b64encode(run_lengths(bytes(cel.pixels.data))).decode()})
    entries = {name: source for name, _, source in part_palette()}
    palette = [{"name": entry.name, "color": f"#{entry.r:02x}{entry.g:02x}{entry.b:02x}",
                "source": entries.get(entry.name)} for entry in sprite.palette.colors[1:]]
    spec = appearance_spec(args.pet)
    # Every color's palette entries for every buyer part, so the site recolors exactly as the CLI does.
    recolors = {part["id"]: {color["id"]: {name: "#%02x%02x%02x" % rgb
                                            for name, rgb in appearance_colors(spec, part["id"], color["id"]).items()}
                             for color in spec["colors"]}
                for part in spec["parts"]}
    examples = {appearance_folder(preset_appearance(spec, preset)): preset_appearance(spec, preset)
                for preset in spec["presets"]}
    data = {
        "source": {"sprite": f"Art/{args.pet}/{args.pet}.aseprite",
                   "sha256": hashlib.sha256(sprite_path(args.pet).read_bytes()).hexdigest()},
        "frame": {"width": FRAME[0], "height": FRAME[1]},
        "scale": SCALE, "cell": {"width": CELL[0], "height": CELL[1]},
        "atlas": {"columns": 8, "rows": len(ROWS) + 2},
        "rows": [{"state": state, "row": row, "durations": DURATIONS[state]} for row, (state, _) in enumerate(ROWS)],
        "frames": frames,
        "palette": palette,
        "appearance": spec,
        "recolors": recolors,
        "folderExamples": examples,
        "license": (Path("Art") / args.pet / "pet-LICENSE.txt").read_text(),
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, separators=(",", ":")) + "\n")
    print(f"Wrote {out}: {len(frames)} frames, {len(palette)} colors, {len(spec['presets'])} presets")


def command_export(args) -> None:
    """Writes each frame as a PNG under its label, and the palette as a 1-pixel-high strip."""
    sprite = Sprite.open(sprite_path(args.pet))
    out = staged(args.pet)
    out.mkdir(parents=True, exist_ok=True)
    for label, image in frame_images(sprite).items():
        image.save(out / f"{label}.png")
    # reduce-colors takes the source colors; the sprite's part ramps repeat them.
    strip = Image.new("RGB", (len(PALETTE), 1))
    for x, (_, rgb) in enumerate(PALETTE):
        strip.putpixel((x, 0), rgb)
    Path("Build/palette").mkdir(parents=True, exist_ok=True)
    strip.save(Path("Build/palette") / f"{args.pet}.png")
    print(f"Exported {len(sprite.frames)} frames to {out} and the palette to Build/palette/{args.pet}.png")


def pack_atlas(sprite: Sprite, pet: str) -> Image.Image:
    """Scales each frame of the sprite up with hard edges and packs the Codex atlas."""
    frames = frame_images(sprite)
    columns, rows = 8, len(ROWS) + 2
    atlas = Image.new("RGBA", (columns * CELL[0], rows * CELL[1]))
    missing = [label for label, _, _ in atlas_cells() if label not in frames]
    if missing:
        raise SystemExit(f"Missing frames in {sprite_path(pet)}: {', '.join(missing)}")
    for label, row, column in atlas_cells():
        frame = frames[label]
        big = frame.resize((frame.width * SCALE, frame.height * SCALE), Image.Resampling.NEAREST)
        # Center the frame across the cell and stand it on the cell's bottom edge.
        x = column * CELL[0] + (CELL[0] - big.width) // 2
        y = row * CELL[1] + CELL[1] - big.height
        atlas.alpha_composite(big, (x, y))
    return atlas


def command_atlas(args) -> None:
    """Packs the default Microduck into Build/pixel/<pet>/, for packaging."""
    atlas = pack_atlas(Sprite.open(sprite_path(args.pet)), args.pet)
    out = Path(args.out) / args.pet
    out.mkdir(parents=True, exist_ok=True)
    atlas.save(out / "spritesheet.png")
    manifest = json.loads((Path("Art") / args.pet / "pet.json").read_text())
    (out / "pet.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Wrote {out / 'spritesheet.png'} from {len(atlas_cells())} frames")


def command_pet(args) -> None:
    """Writes a pet in a buyer's colors, as the customizer site downloads it.

    The folder is named from the appearance, so the same colors always give the same folder,
    and it holds pet.json, a PNG spritesheet, and the license notice.
    """
    spec = appearance_spec(args.pet)
    appearance = parse_appearance(spec, args.appearance)
    sprite = Sprite.open(sprite_path(args.pet))
    apply_appearance(sprite, spec, appearance)
    folder = appearance_folder(appearance)
    out = Path(args.out) / folder
    out.mkdir(parents=True, exist_ok=True)
    pack_atlas(sprite, args.pet).save(out / "spritesheet.png")
    manifest = {"id": folder, "displayName": args.name[:80] or "My Microduck", "description": spec["petDescription"],
                "spriteVersionNumber": 2, "spritesheetPath": "spritesheet.png"}
    (out / "pet.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (out / "LICENSE.txt").write_text((Path("Art") / args.pet / "pet-LICENSE.txt").read_text())
    colors = ", ".join(f"{part} {color}" for part, color in appearance.items())
    print(f"Wrote {out}: {colors}")


def command_outline(args) -> None:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for path in map(Path, args.images):
        outlined(Image.open(path)).save(out / path.name)
    print(f"Outlined {len(args.images)} image(s) into {out}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    inputs = commands.add_parser("inputs", help="make 68 x 68 transfer inputs from raw renders")
    inputs.add_argument("--pet", required=True)
    inputs.add_argument("--raw", default="Build/raw", help="the folder of raw renders")
    inputs.add_argument("--out", default="Build/transfer")
    inputs.set_defaults(run=command_inputs)
    collect = commands.add_parser("collect", help="copy one PixelLab run's frames into Build/art/<pet>")
    collect.add_argument("--pet", required=True)
    collect.add_argument("--run", dest="source", required=True, help="a run folder in Build/pixellab")
    collect.add_argument("--labels", nargs="+", required=True, help="the atlas label for each frame, in order")
    collect.add_argument("--frames", nargs="+", type=int,
                         help="collect only these frames of the run, counting from 0; by default, all of them")
    collect.add_argument("--mirror", nargs="+",
                         help="also save each frame mirrored, under these labels; - skips a frame")
    collect.set_defaults(run=command_collect)
    stage = commands.add_parser("stage", help="restore the outline on correct-pixelart runs, for reduce-colors")
    stage.add_argument("--pet", required=True)
    stage.add_argument("--run", dest="source", nargs="+", required=True, help="correct-pixelart runs in Build/pixellab")
    stage.set_defaults(run=command_stage)
    finish = commands.add_parser("finish", help="write a reduce-colors run into Art/<pet>/<pet>.aseprite")
    finish.add_argument("--pet", required=True)
    finish.add_argument("--run", dest="source", required=True, help="a reduce-colors run in Build/pixellab")
    finish.set_defaults(run=command_finish)
    label = commands.add_parser("label", help="give every pixel of the sprite its part from the part masks")
    label.add_argument("--pet", required=True)
    label.set_defaults(run=command_label)
    assemble = commands.add_parser("assemble", help="build Art/<pet>/<pet>.aseprite from finished frames")
    assemble.add_argument("--pet", required=True)
    assemble.add_argument("--frames", required=True, help="a folder of frames named by atlas label")
    assemble.set_defaults(run=command_assemble)
    site = commands.add_parser("site-data", help="write the customizer's art data from the sprite")
    site.add_argument("--pet", required=True)
    site.add_argument("--out", required=True)
    site.set_defaults(run=command_site_data)
    export = commands.add_parser("export", help="write the sprite's frames and palette as PNGs")
    export.add_argument("--pet", required=True)
    export.set_defaults(run=command_export)
    atlas = commands.add_parser("atlas", help="pack Art/<pet>/<pet>.aseprite into a Codex atlas")
    atlas.add_argument("--pet", required=True)
    atlas.add_argument("--out", default="Build/pixel")
    atlas.set_defaults(run=command_atlas)
    pet = commands.add_parser("pet", help="write a pet in a buyer's colors, as the customizer downloads it")
    pet.add_argument("--pet", required=True)
    pet.add_argument("--appearance", default="", help="a preset and part colors, such as graphite,feet=yellow")
    pet.add_argument("--name", default="My Microduck", help="the pet's name, for pet.json's displayName")
    pet.add_argument("--out", default="Build/appearances")
    pet.set_defaults(run=command_pet)
    outline = commands.add_parser("outline", help="hard alpha and an ink outer ring")
    outline.add_argument("images", nargs="+")
    outline.add_argument("--out", required=True)
    outline.set_defaults(run=command_outline)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
