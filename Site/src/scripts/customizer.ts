// The customizer: recolors Microduck's palette from the visitor's choices,
// animates the chosen row at the ChatGPT app's timings, and builds the pet's
// files in the browser.
import {
  type Appearance,
  appearanceFolder,
  art,
  ATLAS,
  DEFAULT_APPEARANCE,
  frameRgba,
  frames,
  matchingPreset,
  PART_ORDER,
  packAtlas,
  paletteColors,
  paletteRgba,
  presetAppearance,
  spec,
} from "../lib/art";
import { LICENSE_NOTICE, petManifest } from "../lib/pet";
import { zip } from "../lib/zip";

// The ChatGPT app plays idle at six times the contract's frame durations.
const IDLE_SLOWDOWN = 6;

const $ = <T extends Element>(selector: string) => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing ${selector}`);
  return element;
};

const canvas = $<HTMLCanvasElement>("#preview");
const context = canvas.getContext("2d")!;
const caption = $<HTMLElement>("#preview-caption");
const playButton = $<HTMLButtonElement>("#play");
const nameInput = $<HTMLInputElement>("#name");
const status = $<HTMLElement>("#status");
const titles = new Map(spec.colors.map((color) => [color.id, color.title]));

let appearance: Appearance = { ...DEFAULT_APPEARANCE };
let palette = paletteRgba(paletteColors(appearance));

/** Shows the appearance in the swatches, the badge, and the folder name, and redraws. */
async function update() {
  palette = paletteRgba(paletteColors(appearance));
  draw();
  const preset = matchingPreset(appearance);
  for (const radio of document.querySelectorAll<HTMLInputElement>('input[name="preset"]')) {
    radio.checked = radio.value === preset;
  }
  for (const part of PART_ORDER) {
    for (const radio of document.querySelectorAll<HTMLInputElement>(`input[name="part-${part}"]`)) {
      radio.checked = radio.value === appearance[part];
    }
    const chosen = document.querySelector(`fieldset[data-part="${part}"] .chosen`);
    if (chosen) chosen.textContent = titles.get(appearance[part]) ?? appearance[part];
  }
  $<HTMLElement>("#appearance-title").textContent = preset ? titles.get(preset)! : "Custom";
  const current = { ...appearance };
  const name = await appearanceFolder(current);
  // Another choice may have finished first; show only the latest.
  if (PART_ORDER.every((part) => current[part] === appearance[part])) {
    $<HTMLElement>("#folder").textContent = name;
    for (const element of document.querySelectorAll(".folder-name")) element.textContent = name;
  }
}

for (const radio of document.querySelectorAll<HTMLInputElement>('input[name="preset"]')) {
  radio.addEventListener("change", () => {
    if (!radio.checked) return;
    appearance = presetAppearance(radio.value);
    void update();
  });
}
for (const part of PART_ORDER) {
  for (const radio of document.querySelectorAll<HTMLInputElement>(`input[name="part-${part}"]`)) {
    radio.addEventListener("change", () => {
      if (!radio.checked) return;
      appearance = { ...appearance, [part]: radio.value };
      void update();
    });
  }
}
$<HTMLButtonElement>("#reset").addEventListener("click", () => {
  appearance = { ...DEFAULT_APPEARANCE };
  void update();
});

// Animation.
const rowLabels = new Map(
  [...document.querySelectorAll<HTMLInputElement>('input[name="row"]')].map((input) => [
    Number(input.value),
    input.nextElementSibling?.textContent ?? "",
  ]),
);
let row = 0;
let step = 0;
let timer: number | undefined;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
let playing = !reducedMotion.matches;

function rowFrames() {
  const { state, durations } = art.rows[row]!;
  const list = frames.filter((frame) => frame.row === row && frame.label.startsWith(`${state}-`));
  const scale = state === "idle" ? IDLE_SLOWDOWN : 1;
  return list.map((frame, i) => ({ label: frame.label, duration: durations[i]! * scale }));
}

function draw() {
  const list = rowFrames();
  const frame = list[step % list.length]!;
  const image = new ImageData(art.frame.width, art.frame.height);
  image.data.set(frameRgba(frame.label, palette));
  context.putImageData(image, 0, 0);
}

function tick() {
  draw();
  if (!playing) return;
  const list = rowFrames();
  const duration = list[step % list.length]!.duration;
  timer = window.setTimeout(() => {
    step = (step + 1) % list.length;
    tick();
  }, duration);
}

function describe() {
  const label = rowLabels.get(row) ?? "";
  canvas.setAttribute("aria-label", `Your Microduck: ${label.toLowerCase()}`);
  caption.textContent = playing ? `${label}.` : `${label}, paused.`;
  playButton.textContent = playing ? "Pause" : "Play";
}

function restart() {
  window.clearTimeout(timer);
  describe();
  tick();
}

for (const radio of document.querySelectorAll<HTMLInputElement>('input[name="row"]')) {
  radio.addEventListener("change", () => {
    if (!radio.checked) return;
    row = Number(radio.value);
    step = 0;
    restart();
  });
}
playButton.addEventListener("click", () => {
  playing = !playing;
  restart();
});
reducedMotion.addEventListener("change", () => {
  playing = !reducedMotion.matches;
  restart();
});

// The download: a ZIP holding the pet's folder, ready for the pets folder.
async function spritesheet(): Promise<Uint8Array> {
  const sheet = document.createElement("canvas");
  sheet.width = ATLAS.width;
  sheet.height = ATLAS.height;
  const image = new ImageData(ATLAS.width, ATLAS.height);
  image.data.set(packAtlas(palette));
  sheet.getContext("2d")!.putImageData(image, 0, 0);
  // Every pixel is opaque or clear, so the canvas's PNG keeps every color exactly.
  const blob = await new Promise<Blob | null>((resolve) => sheet.toBlob(resolve, "image/png"));
  if (!blob) throw new Error("This browser couldn't encode the spritesheet as PNG.");
  return new Uint8Array(await blob.arrayBuffer());
}

$<HTMLFormElement>("#download").addEventListener("submit", async (event) => {
  event.preventDefault();
  status.textContent = "Drawing your Microduck…";
  try {
    const folder = await appearanceFolder(appearance);
    const manifest = petManifest(nameInput.value, folder);
    const encoder = new TextEncoder();
    const archive = zip([
      { path: `${folder}/pet.json`, data: encoder.encode(`${JSON.stringify(manifest, null, 2)}\n`) },
      { path: `${folder}/spritesheet.png`, data: await spritesheet() },
      { path: `${folder}/LICENSE.txt`, data: encoder.encode(LICENSE_NOTICE) },
    ]);
    const url = URL.createObjectURL(new Blob([archive as Uint8Array<ArrayBuffer>], { type: "application/zip" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = `${folder}.zip`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
    status.textContent = `Downloaded ${folder}.zip. Unzip it into your pets folder to install it.`;
  } catch (error) {
    status.textContent = `Couldn't build the download: ${error instanceof Error ? error.message : error}`;
  }
});

void update();
restart();
