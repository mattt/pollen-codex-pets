// SVG drawings of Microduck from the art, for the icons and the share image.
import { DEFAULT_APPEARANCE, FRAME, frameByLabel, paletteColors, presetAppearance, spec } from "./art";

type Box = { left: number; top: number; width: number; height: number };

/** Rectangles for each run of one color in a frame's rows, inside `box`. */
function rects(label: string, colors: string[], box: Box, x0 = 0, y0 = 0, scale = 1): string {
  const frame = frameByLabel.get(label);
  if (!frame) throw new Error(`No frame ${label}`);
  const out: string[] = [];
  for (let y = box.top; y < box.top + box.height; y++) {
    let x = box.left;
    while (x < box.left + box.width) {
      const index = frame.indices[y * FRAME.width + x]!;
      let end = x + 1;
      while (end < box.left + box.width && frame.indices[y * FRAME.width + end] === index) end++;
      if (index)
        out.push(
          `<rect x="${x0 + (x - box.left) * scale}" y="${y0 + (y - box.top) * scale}" width="${(end - x) * scale}" height="${scale}" fill="${colors[index - 1]}"/>`,
        );
      x = end;
    }
  }
  return out.join("");
}

/** The opaque bounds of a frame's rows from `top` to `bottom`. */
function bounds(label: string, top = 0, bottom = FRAME.height): Box {
  const frame = frameByLabel.get(label)!;
  let left = FRAME.width, right = -1, first = -1, last = -1;
  for (let y = top; y < bottom; y++)
    for (let x = 0; x < FRAME.width; x++)
      if (frame.indices[y * FRAME.width + x]) {
        left = Math.min(left, x);
        right = Math.max(right, x);
        if (first < 0) first = y;
        last = y;
      }
  return { left, top: first, width: right - left + 1, height: last - first + 1 };
}

/** The favicon mark: the default Microduck's head, facing the viewer. */
export function headMark(): string {
  const label = "neutral";
  const whole = bounds(label);
  // The head is the top 40 percent of the standing figure.
  const head = bounds(label, whole.top, whole.top + Math.round(whole.height * 0.4));
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${head.width} ${head.height}" shape-rendering="crispEdges">${rects(label, paletteColors(DEFAULT_APPEARANCE), head)}</svg>`;
}

/** The share image: Microduck in each factory preset, on a light stage. */
export function shareSvg(width: number, height: number, background: string): string {
  const scale = 6;
  const box = bounds("idle-0");
  const gap = Math.floor((width - spec.presets.length * box.width * scale) / (spec.presets.length + 1));
  const y = Math.floor((height - box.height * scale) / 2);
  const ducks = spec.presets
    .map((preset, i) => rects("idle-0", paletteColors(presetAppearance(preset)), box, gap + i * (box.width * scale + gap), y, scale))
    .join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" shape-rendering="crispEdges"><rect width="${width}" height="${height}" fill="${background}"/>${ducks}</svg>`;
}
