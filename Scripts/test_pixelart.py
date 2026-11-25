# /// script
# requires-python = ">=3.12"
# dependencies = ["aseprite[image]>=0.1", "pillow>=11"]
# ///
"""Run with `uv run Scripts/test_pixelart.py`."""

import json
import shutil
import unittest
from argparse import Namespace
from contextlib import chdir
from pathlib import Path
from tempfile import TemporaryDirectory

from aseprite import ColorMode, Pixels, Sprite, UserData

import pixelart


class SiteDataTests(unittest.TestCase):
    def test_missing_final_frame_preserves_previous_export(self):
        variants = Path(__file__).resolve().parents[1] / "Art/microduck/variants.json"
        with TemporaryDirectory() as directory, chdir(directory):
            source = pixelart.sprite_path("fixture")
            source.parent.mkdir(parents=True)
            shutil.copy(variants, source.parent)
            (source.parent / "pet-LICENSE.txt").write_text("Test fixture\n")

            sprite = Sprite(*pixelart.FRAME, ColorMode.INDEXED, empty=True)
            sprite.add_layer("fixture")
            sprite.palette = pixelart.palette()
            cells = pixelart.sprite_cells()
            for label, duration in cells:
                frame = sprite.add_frame(duration)
                cel = frame.set_cel(0, Pixels.blank(*pixelart.FRAME, ColorMode.INDEXED))
                cel.user_data = UserData(text=label)
            sprite.save(source)

            out = Path("site-data.json")
            args = Namespace(pet="fixture", out=out)
            pixelart.command_site_data(args)
            previous = out.read_bytes()
            self.assertEqual(len(json.loads(previous)["frames"]), len(cells))

            sprite.frames.pop()
            sprite.save(source)
            with self.assertRaisesRegex(SystemExit, f"Missing frame {cells[-1][0]} "):
                pixelart.command_site_data(args)
            self.assertEqual(out.read_bytes(), previous)


if __name__ == "__main__":
    unittest.main()
