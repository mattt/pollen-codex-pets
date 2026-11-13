# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx", "pillow>=11"]
# ///
"""Call PixelLab's v2 REST API for the pixel-art pets.

    uv run Scripts/pixellab.py balance
    uv run Scripts/pixellab.py sheet Build/pixellab/<run>
    uv run Scripts/pixellab.py image --description TEXT --size WxH --reference PNG... [--style PNG] --label NAME
    uv run Scripts/pixellab.py edit --size WxH (--reference PNG | --description TEXT) --label NAME IMAGE.png...
    uv run Scripts/pixellab.py rotations --first-frame PNG --label NAME
    uv run Scripts/pixellab.py transfer --reference PNG --size WxH --label NAME FRAME.png...
    uv run Scripts/pixellab.py correct [--strength N] --label NAME FRAME.png...
    uv run Scripts/pixellab.py reduce [--colors N | --palette PNG] --label NAME FRAME.png...

The token comes from `PIXELLAB_API_TOKEN` and is sent only to api.pixellab.ai.
Every paid run writes its outputs, a 4x contact sheet on a checkerboard,
and a `run.json` record of the settings and the spend to `Build/pixellab/<stamp>-<label>/`.
Set `PIXELLAB_DRY_RUN=1` to print a request's shape without sending it.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import sys
import time
from pathlib import Path

import httpx
from PIL import Image, ImageDraw

BASE_URL = "https://api.pixellab.ai/v2"
POLL_SECONDS = 5
POLL_TIMEOUT = 900
HTTP_TIMEOUT = 60.0


def headers() -> dict:
    token = os.environ.get("PIXELLAB_API_TOKEN")
    if not token:
        sys.exit("Set PIXELLAB_API_TOKEN in the environment.")
    return {"Authorization": f"Bearer {token}"}


def post(path: str, payload: dict, timeout: float = HTTP_TIMEOUT) -> dict:
    if os.environ.get("PIXELLAB_DRY_RUN"):
        def shape(value):
            if isinstance(value, dict):
                return {k: "<image>" if k == "base64" else shape(v) for k, v in value.items()}
            if isinstance(value, list):
                return [shape(v) for v in value]
            return value
        print(f"Dry run: POST {path}\n{json.dumps(shape(payload), indent=1)}")
        sys.exit(0)
    response = httpx.post(f"{BASE_URL}{path}", headers=headers(), json=payload, timeout=timeout)
    if response.status_code >= 400:
        sys.exit(f"POST {path} -> {response.status_code}: {response.text[:800]}")
    return response.json()


def get(path: str) -> dict:
    response = httpx.get(f"{BASE_URL}{path}", headers=headers(), timeout=HTTP_TIMEOUT)
    if response.status_code >= 400:
        sys.exit(f"GET {path} -> {response.status_code}: {response.text[:800]}")
    return response.json()


def wait(job_id: str) -> dict:
    """Polls a background job and returns the finished job."""
    waited = 0
    while waited < POLL_TIMEOUT:
        time.sleep(POLL_SECONDS)
        waited += POLL_SECONDS
        job = get(f"/background-jobs/{job_id}")
        status = job.get("status")
        print(f"  job {job_id}: {status} ({waited} s)", flush=True)
        if status in ("completed", "success", "done", "finished"):
            return job
        if status in ("failed", "error", "cancelled"):
            sys.exit(f"Job failed: {json.dumps(job)[:800]}")
    sys.exit(f"Job {job_id} timed out after {POLL_TIMEOUT} s")


def encoded(path: Path) -> dict:
    with Image.open(path) as image:
        width, height = image.size
    data = base64.b64encode(path.read_bytes()).decode()
    return {"image": {"type": "base64", "base64": data, "format": "png"},
            "size": {"width": width, "height": height}}


def images_in(value, found: list) -> list:
    """Every image in a response, in order."""
    if isinstance(value, dict):
        if isinstance(value.get("base64"), str):
            found.append(value)
        else:
            for child in value.values():
                images_in(child, found)
    elif isinstance(value, list):
        for child in value:
            images_in(child, found)
    return found


def decode(entry: dict) -> Image.Image:
    data = entry["base64"]
    if data.startswith("data:"):
        data = data.split(",", 1)[1]
    raw = base64.b64decode(data)
    if entry.get("type") == "rgba_bytes":
        return Image.frombytes("RGBA", (entry["width"], entry["height"]), raw)
    return Image.open(io.BytesIO(raw)).convert("RGBA")


def contact_sheet(paths: list[Path], out: Path, scale: int = 4) -> None:
    """Lays out images at `scale`x with hard edges over a checkerboard, numbered by position."""
    images = [Image.open(path).convert("RGBA") for path in paths]
    cell_width = max(image.width for image in images) * scale
    cell_height = max(image.height for image in images) * scale
    columns = min(len(images), 8)
    rows = (len(images) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_width, rows * cell_height))
    draw = ImageDraw.Draw(sheet)
    for index, image in enumerate(images):
        x, y = (index % columns) * cell_width, (index // columns) * cell_height
        for ty in range(0, cell_height, 8):
            for tx in range(0, cell_width, 8):
                shade = 200 if (tx // 8 + ty // 8) % 2 else 160
                sheet.paste((shade, shade, shade, 255), (x + tx, y + ty, x + min(tx + 8, cell_width), y + min(ty + 8, cell_height)))
        big = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
        sheet.alpha_composite(big, (x + (cell_width - big.width) // 2, y + (cell_height - big.height) // 2))
        draw.rectangle((x, y, x + 22, y + 16), fill=(16, 16, 24, 255))
        draw.text((x + 4, y + 2), f"{index:02d}", fill=(255, 248, 232, 255))
    sheet.save(out)


def run_directory(label: str) -> Path:
    directory = Path("Build/pixellab") / f"{time.strftime('%Y%m%d-%H%M%S')}-{label}"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def save_results(job: dict, directory: Path, record: dict, unique: bool = True) -> None:
    # Some endpoints list each frame twice, so keep the first copy of each image,
    # unless each output answers one input.
    seen = set()
    images = [entry for entry in images_in(job.get("last_response") or job, [])
              if not unique or not (entry["base64"] in seen or seen.add(entry["base64"]))]
    if not images:
        sys.exit("The job finished without images.")
    paths = []
    for index, entry in enumerate(images):
        path = directory / f"{index:02d}.png"
        decode(entry).save(path)
        paths.append(path)
    contact_sheet(paths, directory / "sheet.png")
    record["usage"] = job.get("usage")
    record["outputs"] = [path.name for path in paths]
    (directory / "run.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"Wrote {len(paths)} image(s), sheet.png, and run.json to {directory}")
    print(f"Usage: {job.get('usage')}")


def size(value: str) -> dict:
    width, height = (int(part) for part in value.lower().split("x"))
    return {"width": width, "height": height}


def command_sheet(args) -> None:
    directory = Path(args.directory)
    paths = sorted(path for path in directory.glob("[0-9][0-9].png"))
    contact_sheet(paths, directory / "sheet.png")
    print(f"Wrote {directory / 'sheet.png'}")


def command_balance(args) -> None:
    print(json.dumps(get("/balance"), indent=2))


def command_image(args) -> None:
    if len(args.reference_usage) not in (0, len(args.reference)):
        sys.exit("Give one --reference-usage for each --reference, or none.")
    usages = args.reference_usage or ["Generate this character in this pose"] * len(args.reference)
    references = []
    for path, usage in zip(args.reference, usages):
        reference = encoded(Path(path))
        reference["usage_description"] = usage
        references.append(reference)
    payload = {
        "description": args.description,
        "image_size": size(args.size),
        "no_background": True,
        "reference_images": references,
    }
    if args.style:
        style = encoded(Path(args.style))
        style["usage_description"] = args.style_usage
        payload["style_image"] = style
        payload["style_options"] = {"color_palette": args.palette, "outline": True, "detail": True, "shading": True}
    if args.seed is not None:
        payload["seed"] = args.seed
    response = post("/generate-image-v2", payload)
    directory = run_directory(args.label)
    job = wait(response["background_job_id"])
    save_results(job, directory, {
        "endpoint": "generate-image-v2", "job": response["background_job_id"],
        "description": args.description, "size": args.size, "seed": args.seed,
        "references": args.reference, "reference_usages": usages,
        "style": args.style, "style_usage": args.style_usage if args.style else None,
        "style_palette": args.palette if args.style else None,
    })


def flat(path: Path) -> dict:
    """An image in the edit endpoint's schema, which puts the size beside the image."""
    image = encoded(path)
    return {"image": image["image"], **image["size"]}


def command_edit(args) -> None:
    if bool(args.reference) == bool(args.description):
        sys.exit("Give either --reference, to match its style, or --description, to edit with text.")
    payload = {
        "method": "edit_with_reference" if args.reference else "edit_with_text",
        "edit_images": [flat(Path(path)) for path in args.images],
        "image_size": size(args.size),
        "no_background": True,
    }
    if args.reference:
        payload["reference_image"] = flat(Path(args.reference))
    else:
        payload["description"] = args.description
    if args.seed is not None:
        payload["seed"] = args.seed
    response = post("/edit-images-v2", payload)
    directory = run_directory(args.label)
    job = wait(response["background_job_id"])
    save_results(job, directory, {
        "endpoint": "edit-images-v2", "job": response["background_job_id"], "method": payload["method"],
        "images": args.images, "reference": args.reference, "description": args.description,
        "size": args.size, "seed": args.seed,
    })


def command_rotations(args) -> None:
    payload = {
        "first_frame": encoded(Path(args.first_frame))["image"],
        "description": args.description,
        "no_background": True,
        "seed": args.seed,
    }
    response = post("/generate-8-rotations-v3", payload)
    directory = run_directory(args.label)
    job = wait(response["background_job_id"])
    save_results(job, directory, {
        "endpoint": "generate-8-rotations-v3", "job": response["background_job_id"],
        "first_frame": args.first_frame, "description": args.description, "seed": args.seed,
    })


def command_transfer(args) -> None:
    payload = {
        "reference_image": encoded(Path(args.reference)),
        "frames": [encoded(Path(frame)) for frame in args.frames],
        "image_size": size(args.size),
        "no_background": True,
        "additional_instructions": args.instructions,
    }
    if args.seed is not None:
        payload["seed"] = args.seed
    response = post("/transfer-outfit-v2", payload)
    directory = run_directory(args.label)
    job = wait(response["background_job_id"])
    save_results(job, directory, {
        "endpoint": "transfer-outfit-v2", "job": response["background_job_id"],
        "reference": args.reference, "frames": args.frames, "size": args.size,
        "instructions": args.instructions, "seed": args.seed,
    })


def command_correct(args) -> None:
    payload = {"images": [encoded(Path(path))["image"] for path in args.images], "strength": args.strength}
    response = post("/correct-pixelart", payload, timeout=300)
    directory = run_directory(args.label)
    save_results({"images": response["images"], "usage": response.get("usage")}, directory, {
        "endpoint": "correct-pixelart", "images": args.images, "strength": args.strength,
    }, unique=False)


def command_reduce(args) -> None:
    payload = {"images": [encoded(Path(path))["image"] for path in args.images], "dithering": "none"}
    if args.colors:
        payload["num_colors"] = args.colors
    if args.palette:
        payload["palette_image"] = encoded(Path(args.palette))["image"]
    response = post("/reduce-colors", payload, timeout=300)
    directory = run_directory(args.label)
    decode(response["palette"]).save(directory / "palette.png")
    save_results({"images": response["images"], "usage": response.get("usage")}, directory, {
        "endpoint": "reduce-colors", "images": args.images, "requested_colors": args.colors,
        "palette": args.palette, "colors": response["n_colors"],
    }, unique=False)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("balance", help="show credits and remaining generations").set_defaults(run=command_balance)

    sheet = commands.add_parser("sheet", help="rebuild a run's numbered contact sheet")
    sheet.add_argument("directory")
    sheet.set_defaults(run=command_sheet)

    image = commands.add_parser("image", help="generate candidates with PixelLab Pro")
    image.add_argument("--description", required=True)
    image.add_argument("--size", required=True, help="output size, such as 64x64")
    image.add_argument("--reference", action="append", required=True,
                       help="subject reference image; repeat for up to 4")
    image.add_argument("--reference-usage", action="append", default=[],
                       help="how to use each reference, in the same order")
    image.add_argument("--style", help="style image")
    image.add_argument("--style-usage", default="Copy the outline, shading, and detail; keep the subject's own colors")
    image.add_argument("--palette", action="store_true", help="also copy the style image's palette")
    image.add_argument("--seed", type=int)
    image.add_argument("--label", required=True)
    image.set_defaults(run=command_image)

    edit = commands.add_parser("edit", help="restyle images to match a reference, or edit them with text")
    edit.add_argument("--size", required=True, help="output size, such as 64x64")
    edit.add_argument("--reference", help="match this image's style")
    edit.add_argument("--description", help="edit with this text instead")
    edit.add_argument("--seed", type=int)
    edit.add_argument("--label", required=True)
    edit.add_argument("images", nargs="+", help="1 to 15 images, edited together")
    edit.set_defaults(run=command_edit)

    rotations = commands.add_parser("rotations", help="turn one sprite to face 8 directions")
    rotations.add_argument("--first-frame", required=True, help="the sprite, facing the viewer")
    rotations.add_argument("--description", default=None)
    rotations.add_argument("--seed", type=int, default=0)
    rotations.add_argument("--label", required=True)
    rotations.set_defaults(run=command_rotations)

    transfer = commands.add_parser("transfer", help="apply a reference look to animation frames")
    transfer.add_argument("--reference", required=True, help="the look to apply")
    transfer.add_argument("--size", required=True, help="frame size, such as 68x68")
    transfer.add_argument("--instructions", default="")
    transfer.add_argument("--seed", type=int)
    transfer.add_argument("--label", required=True)
    transfer.add_argument("frames", nargs="+", help="2 to 15 frames, in order")
    transfer.set_defaults(run=command_transfer)

    correct = commands.add_parser("correct", help="clean up pixel art on its own grid")
    correct.add_argument("--strength", type=float, default=0.1,
                         help="0 to 1; low values tidy stray pixels, high values redraw")
    correct.add_argument("--label", required=True)
    correct.add_argument("images", nargs="+", help="same-size frames, corrected together")
    correct.set_defaults(run=command_correct)

    reduce = commands.add_parser("reduce", help="quantize frames onto one shared palette")
    choice = reduce.add_mutually_exclusive_group()
    choice.add_argument("--colors", type=int, help="palette size; detected from the frames if omitted")
    choice.add_argument("--palette", help="reuse this image's colors, such as an earlier run's palette.png")
    reduce.add_argument("--label", required=True)
    reduce.add_argument("images", nargs="+", help="same-size frames, at most 512 x 512 pixels in all")
    reduce.set_defaults(run=command_reduce)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
