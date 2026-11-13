import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import sharp from "sharp";
import { describe, expect, test } from "vite-plus/test";
import {
  appearanceEncoding,
  appearanceFolder,
  art,
  ATLAS,
  DEFAULT_APPEARANCE,
  matchingPreset,
  packAtlas,
  paletteColors,
  paletteRgba,
  presetAppearance,
  spec,
} from "./art";

describe("folder names", () => {
  test("the encoding is versioned and lists the parts in a fixed order", () => {
    expect(appearanceEncoding({ feet: "yellow", beak: "orange", body: "sky", head: "graphite" })).toBe(
      "microduck-appearance/1 head=graphite body=sky beak=orange feet=yellow",
    );
  });

  test("the default Cream pet has a known folder", async () => {
    // SHA-256("microduck-appearance/1 head=cream body=cream beak=orange feet=orange") starts 2aae1a7.
    expect(await appearanceFolder(DEFAULT_APPEARANCE)).toBe("microduck-2aae1a7");
  });

  test("the site names every preset's folder as pixelart.py does", async () => {
    for (const [folder, appearance] of Object.entries(art.folderExamples)) {
      expect(await appearanceFolder(appearance)).toBe(folder);
    }
  });

  test("no appearance is named microduck, the packaged pet's folder", async () => {
    const folders = new Set<string>();
    for (const head of spec.colors) {
      for (const beak of spec.colors) {
        const folder = await appearanceFolder({ head: head.id, body: head.id, beak: beak.id, feet: beak.id });
        expect(folder).toMatch(/^microduck-[0-9a-f]{7}$/);
        folders.add(folder);
      }
    }
    expect(folders.size).toBe(spec.colors.length ** 2);
  });
});

describe("appearances", () => {
  test("a preset sets the head and body to its color, and the beak and feet to orange", () => {
    expect(presetAppearance("lavender")).toEqual({ head: "lavender", body: "lavender", beak: "orange", feet: "orange" });
    expect(matchingPreset(presetAppearance("sky"))).toBe("sky");
    expect(matchingPreset({ ...presetAppearance("sky"), feet: "yellow" })).toBeNull();
  });

  test("the default appearance leaves the art's colors unchanged", () => {
    expect(paletteColors(DEFAULT_APPEARANCE)).toEqual(art.palette.map((entry) => entry.color));
  });
});

const built = fileURLToPath(new URL("../../../Build/pixel/microduck/spritesheet.png", import.meta.url));
const graphite = fileURLToPath(new URL("../../../Build/appearances/microduck-33fcdb3/spritesheet.png", import.meta.url));

describe("atlas", () => {
  async function pixels(file: string) {
    const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    expect([info.width, info.height]).toEqual([ATLAS.width, ATLAS.height]);
    return data;
  }

  test.skipIf(!existsSync(built))("the default matches pixelart.py's atlas pixel for pixel", async () => {
    const atlas = packAtlas(paletteRgba(paletteColors(DEFAULT_APPEARANCE)));
    expect(Buffer.from(atlas).equals(await pixels(built))).toBe(true);
  });

  test.skipIf(!existsSync(graphite))("Graphite matches pixelart.py pet's atlas pixel for pixel", async () => {
    const atlas = packAtlas(paletteRgba(paletteColors(presetAppearance("graphite"))));
    expect(Buffer.from(atlas).equals(await pixels(graphite))).toBe(true);
  });
});
