// Microduck's art data, written from Art/microduck/microduck.aseprite by
// `pixelart.py site-data` at build time, and the functions that recolor it
// and pack a Codex atlas. The shade derivation matches pixelart.py's, so the
// customizer and the command-line variants give the same colors.
import data from "../generated/microduck.json";

export type ArtData = typeof data;
export type ColorId = string;
/** A color for each of the four parts that a buyer chooses: head, body, beak, and feet. */
export type Appearance = { head: ColorId; body: ColorId; beak: ColorId; feet: ColorId };

export const art = data;
export const spec = data.appearance;
export const PART_ORDER = ["head", "body", "beak", "feet"] as const;
export const FRAME = data.frame;
export const ATLAS = {
  width: data.atlas.columns * data.cell.width,
  height: data.atlas.rows * data.cell.height,
};

export function parseHex(hex: string): [number, number, number] {
  const match = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!match) throw new Error(`Not a #rrggbb color: ${hex}`);
  const value = Number.parseInt(match[1]!, 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

/** A factory preset: the head and body in the preset's color, the beak and feet in the accent. */
export function presetAppearance(preset: ColorId): Appearance {
  return { head: preset, body: preset, beak: spec.presetAccent, feet: spec.presetAccent };
}

export const DEFAULT_APPEARANCE = presetAppearance(spec.default);

/** The preset that an appearance matches, or null when it's custom. */
export function matchingPreset(appearance: Appearance): ColorId | null {
  return (
    spec.presets.find((preset) => {
      const candidate = presetAppearance(preset);
      return PART_ORDER.every((part) => candidate[part] === appearance[part]);
    }) ?? null
  );
}

/**
 * The canonical, versioned encoding of an appearance, which names its folder:
 * `microduck-appearance/1 head=<color> body=<color> beak=<color> feet=<color>`,
 * with single spaces and no newline. pixelart.py's appearance_folder uses the same.
 */
export function appearanceEncoding(appearance: Appearance): string {
  return `microduck-appearance/1 ${PART_ORDER.map((part) => `${part}=${appearance[part]}`).join(" ")}`;
}

/** The pet's folder: microduck- and the first 7 hex digits of the encoding's SHA-256. */
export async function appearanceFolder(appearance: Appearance): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(appearanceEncoding(appearance)));
  const hex = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `microduck-${hex.slice(0, 7)}`;
}

/**
 * The palette's colors, after the transparent entry, for an appearance.
 * pixelart.py site-data precomputes each part's colors for each color,
 * so the site recolors exactly as the command line does.
 */
export function paletteColors(appearance: Appearance): string[] {
  const colors = new Map(data.palette.map((entry) => [entry.name, entry.color]));
  for (const part of PART_ORDER) {
    const recolor = (data.recolors as Record<string, Record<string, Record<string, string>>>)[part]?.[appearance[part]];
    if (!recolor) throw new Error(`No color ${appearance[part]} for the ${part}`);
    for (const [name, color] of Object.entries(recolor)) colors.set(name, color);
  }
  return data.palette.map((entry) => colors.get(entry.name)!);
}

/** RGBA for each palette index; index 0 is transparent. */
export function paletteRgba(colors: string[]): Uint8ClampedArray {
  const rgba = new Uint8ClampedArray((colors.length + 1) * 4);
  colors.forEach((color, i) => {
    rgba.set([...parseHex(color), 255], (i + 1) * 4);
  });
  return rgba;
}

function decodeBase64(text: string): Uint8Array {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** Each frame's palette indices, 64 × 68, from its run lengths. */
export const frames = data.frames.map((frame) => {
  const runs = decodeBase64(frame.pixels);
  const indices = new Uint8Array(FRAME.width * FRAME.height);
  let offset = 0;
  for (let i = 0; i < runs.length; i += 2) {
    indices.fill(runs[i + 1]!, offset, offset + runs[i]!);
    offset += runs[i]!;
  }
  if (offset !== indices.length) throw new Error(`Frame ${frame.label} has ${offset} pixels`);
  return { ...frame, indices };
});

export const frameByLabel = new Map(frames.map((frame) => [frame.label, frame]));

/** One frame as RGBA at its own size. */
export function frameRgba(label: string, palette: Uint8ClampedArray): Uint8ClampedArray {
  const frame = frameByLabel.get(label);
  if (!frame) throw new Error(`No frame ${label}`);
  const rgba = new Uint8ClampedArray(frame.indices.length * 4);
  frame.indices.forEach((index, i) => {
    if (index) rgba.set(palette.subarray(index * 4, index * 4 + 4), i * 4);
  });
  return rgba;
}

/**
 * The Codex atlas as RGBA: each frame scaled up with hard edges, centered across
 * its cell and standing on the cell's bottom edge, as pixelart.py's atlas does.
 */
export function packAtlas(palette: Uint8ClampedArray): Uint8ClampedArray {
  const { width, height } = ATLAS;
  const scale = data.scale;
  const atlas = new Uint8ClampedArray(width * height * 4);
  for (const frame of frames) {
    const left = frame.column * data.cell.width + Math.floor((data.cell.width - FRAME.width * scale) / 2);
    const top = frame.row * data.cell.height + data.cell.height - FRAME.height * scale;
    for (let y = 0; y < FRAME.height; y++) {
      for (let x = 0; x < FRAME.width; x++) {
        const index = frame.indices[y * FRAME.width + x]!;
        if (!index) continue;
        const color = palette.subarray(index * 4, index * 4 + 4);
        for (let dy = 0; dy < scale; dy++) {
          const row = (top + y * scale + dy) * width;
          for (let dx = 0; dx < scale; dx++) atlas.set(color, (row + left + x * scale + dx) * 4);
        }
      }
    }
  }
  return atlas;
}
