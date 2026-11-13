# Pollen Codex Pets

Pollen Codex Pets makes Codex pets for the ChatGPT app
from the robots in [Pollen Pet](https://github.com/mattt/PollenPet).
Choose [Microduck](https://pollen-robotics.com/microduck/)
or [Reachy Mini](https://pollen-robotics.com/reachy-mini/)
from [Pollen Robotics](https://pollen-robotics.com)
to keep you company while Codex works.

> [!NOTE]
> Pollen Codex Pets is an independent, noncommercial project.
> The Microduck model and its spritesheet are licensed for noncommercial use only.

## Installation

Copy the pets into the Codex pets folder:

```bash
Scripts/install.sh
```

The script copies `Pets/microduck` and `Pets/reachy-mini`
into `${CODEX_HOME:-~/.codex}/pets`.
To install one pet, pass its ID, such as `Scripts/install.sh reachy-mini`.
The app identifies each pet by its folder name.

In the ChatGPT app, open Settings, choose Mini & Pets,
and select the pet under My pets.
Then type `/pet` in the composer to wake the pet or tuck it away.
To remove a pet, delete its folder from the pets folder.

## Pets

Each pet is a Codex v2 pet:
a `pet.json` manifest and a 1536 × 2288 spritesheet
with nine animation rows and sixteen look directions.
Microduck is 16-bit pixel art, like the Codex pets built into the ChatGPT app.
Reachy Mini is a rendering of its 3D model.

Each pet moves only as the real robot can.
Neither robot can jump, so each celebrates another way.
Reachy Mini can't walk, so it turns in the direction that you drag it.
Except in the looks, Microduck turns three-quarters,
toward the right except when it walks left,
to show its silhouette:
the large head held forward on its neck and the white thigh shells.

| Row | State           | Microduck                                         | Reachy Mini                                           |
| --- | --------------- | ------------------------------------------------- | ----------------------------------------------------- |
| 0   | `idle`          | Breathes, glances aside, and clicks its beak      | Drifts its antennas and head                          |
| 1   | `running-right` | Waddles to the right in short, low steps          | Turns right and bobs its head, antennas flapping      |
| 2   | `running-left`  | Waddles to the left in short, low steps           | Turns left and bobs its head                          |
| 3   | `waving`        | Dips its head, then quacks hello                  | Waves one antenna                                     |
| 4   | `jumping`       | Squashes, stretches tall to quack, and wiggles    | Spins once on its base, antennas thrown wide          |
| 5   | `failed`        | Gasps, wobbles, and slumps onto its face          | Droops both antennas and hangs its head               |
| 6   | `waiting`       | Sits on its folded legs and calls up to you       | Tilts its head and twitches one antenna               |
| 7   | `running`       | Chatters through the task, bobbing its head       | Scans its work while its antennas sweep               |
| 8   | `review`        | Inspects from each side, pecks once, and nods     | Points its antennas in, inspects, and nods            |
| 9–10 | look           | Turns its head toward the pointer                 | Turns its body and head; the antennas trail           |

## How it works

Both pets start in 3D.
A Swift command-line tool, `render-pets`,
loads each robot's USDZ model in RealityKit
and renders every cell offscreen with `RealityRenderer`.
It uses Pollen Pet's camera direction, sky-and-ground lighting,
and default Microduck colors.

Each robot has a rig that turns its real joints:

- **Microduck** turns its neck, head, and beak servos,
  and the hip, knee, and ankle servos of both legs.
  Like the real robot, it rests with its knees bent, its body low,
  and its neck tipped forward to hold its head forward and level.
  Every row is an offset from that rest posture.
  Every joint stays within the real servo's range,
  and the renderer warns if a pose exceeds it.
  After each pose, the stage sets the lowest point of any part on the floor,
  so steps stay grounded, and sitting and falling poses rest on the floor.
- **Reachy Mini** turns its body on its base,
  moves its head on its platform,
  and swings each antenna on its motor.

`Choreography.swift` gives the pose for every cell.
The atlas builder renders each pose at 1200 × 1200 pixels,
finds one scale and one floor line that fit every pose,
and resamples each frame into a 192 × 208 cell.
The shared scale and floor line keep the robot's size consistent between frames.
Like the character stickers in Pollen Pet,
each rendered robot has a 2-pixel ink line and a thin paper border,
so it is visible on both light and dark desktops.
This atlas is the Reachy Mini spritesheet.
Microduck's spritesheet is pixel art,
which has a 1-pixel ink outline and no paper border.

### Microduck's pixel art

[PixelLab](https://pixellab.ai) draws Microduck's frames
over the 3D renders,
so they keep the real robot's proportions:
a narrow upright body, short legs with the knees forward,
and a large head held forward on a long neck.

1. **Renders.**
   With `--raw`, the renderer writes every cell at twice the cell size,
   with no outline, to `Build/raw/`.
   Every render shares the atlas's scale and floor line.
2. **Transfer inputs.**
   `Scripts/pixelart.py inputs` scales each render down
   to the 64 × 68 pixel-art frame with a box filter,
   and centers it at the bottom of a transparent 68 × 68 canvas.
   PixelLab's frame transfer rejects 64 × 68,
   which falls between two of its size tiers;
   68 × 68 is in the 64–80 pixel tier,
   which takes 9 images per call.
   The reference takes one of those, so a call holds at most 8 frames.
3. **Frame transfer.**
   PixelLab's `transfer-outfit-v2` restyles each row's renders together
   as pixel art and keeps each frame's pose and floor line.
   Every call uses the same reference, `Art/microduck/style.png`,
   a finished frame of the walk,
   and the same instructions, which name the colors,
   so that the rows share one look.
   PixelLab sometimes refuses a call as "against policy"
   without charging for it; the same call succeeded on a retry.
   Only drawn frames, those that aren't mirrored or copied from another frame,
   go to PixelLab.
   The trot faces three-quarters right, and the trot to the left mirrors it.
   The looks from 202.5° to 337.5° mirror the looks from 157.5° to 22.5°.
   The looks need 9 drawn frames, one more than a call takes,
   so 180° has its own call, with the neutral frame.
   The rows that stay in place turn three-quarters, like the walk.
   For comparison, `render-pets --view front`, or `mise run pixel:inputs:front`,
   renders them facing the viewer, to `Build/front/`.
   The walk, the fall, and the looks are the same in both views.
4. **Collection.**
   `pixelart.py collect` crops each frame back to 64 × 68,
   adds a clean 1-pixel ink outline, and saves it with the mirrored frames
   to `Build/art/microduck/`.
   It records each frame's source in `Art/microduck/provenance.json`.
5. **Cleanup.**
   PixelLab's `correct-pixelart` tidies each row's collected frames together.
   `pixelart.py stage` restores their outline,
   and `reduce-colors` puts them on the sprite's palette,
   which `pixelart.py export` writes to `Build/palette/microduck.png`.
   `pixelart.py finish` restores the outline again,
   preserves each frame's floor line from before cleanup,
   repairs the feet,
   and writes the frames, with the mirrored frames, into the sprite.
6. **The sprite.**
   `Art/microduck/microduck.aseprite` is the single source of the art:
   indexed color, one 64 × 68 frame per atlas cell in atlas order,
   a tag for each row, for `neutral`, and for the looks,
   and each cel's atlas label in its user data.
   Its palette has `ink` for the outline
   and one named ramp, such as `head-0` to `head-5`,
   for each part, so that each can be recolored:
   `head`, `beak`, `mouth` (the inside of the mouth), `ring` (the lens ring),
   `lens`, `face`, `body`, `thighs`, `brackets`, `feet`, `ankles`, `soles`, and `servos`.
   A buyer colors only four parts; see [Colors](#colors).
   The head, body, and beak each have a second ramp with the same colors,
   such as `head-rim-0`,
   for their pixels that touch the outline or a gray part.
   Each ramp repeats the colors of its part's material:
   six cream shades for the shells, three oranges for the beak and feet,
   and five grays for the servos, lens, and face.
   The lens ring has oranges and grays, because PixelLab drew it both ways.
   PixelLab's runs are quantized onto the palette's 15 source colors:
   `ink` and those 14 material colors.
   The scripts read and write the sprite
   with [aseprite-py](https://github.com/mattt/aseprite-py)
   and never open the Aseprite app.
   Git LFS stores the file.
   `pixelart.py assemble` rebuilds it from a folder of frames,
   such as the one that `pixelart.py export` writes.
7. **Feet.**
   PixelLab left pale specks and a gray band on the orange soles,
   from the model's teal pads, and some doubled outline pixels.
   `finish` and `assemble` repair them with fixed rules near each foot,
   and record the number of pixels changed in each frame in `provenance.json`.
   They change only pixels next to a foot's orange.
8. **Parts.**
   With `--mask`, the renderer draws every cell again
   with each part in one flat color and no lighting,
   cropped as the raw renders are; `mise run render` writes these masks to `Build/mask/`.
   Each pixel of the sprite takes the part under it in the mask
   when its color fits that part's material.
   Where the two disagree, such as where PixelLab's drawing strays from the render,
   the pixel takes the most common part nearby that its color allows.
   `finish` labels new frames this way,
   and `mise run pixel:label` relabels the whole sprite.
9. **Finishing.**
   `pixelart.py atlas` scales each 64 × 68 frame up 3× with hard edges
   and packs the atlas.
   The renderer opens the beak, and frame transfer keeps the opening,
   so the chatter and the quacks need no change in code.

#### Colors

A buyer chooses Microduck's colors as for the physical robot,
and as in [Pollen Pet](https://github.com/mattt/PollenPet):
six colors (cream, graphite, lavender, sky, orange, and yellow),
four factory presets (cream, graphite, lavender, and sky),
and four parts
(the head, which includes the inside of the mouth; the body; the beak; and the feet).
A preset sets the head and body to its color, and the beak and feet to orange.
The feet include the ankle brackets and the soles' orange,
because together they make the colored block that a buyer sees as the foot;
Pollen Pet colors only the foot shells.
Every other part keeps the default art's colors.
`Art/microduck/variants.json` lists the colors, presets, and parts,
and the colors are visual approximations.
Each color becomes an art base color for its part's ramp,
by the same change in saturation and brightness
that turns the renderer's paint into the default art,
so that it looks as lit as the default does.
Graphite also lightens the rim ramps of the head, body, and beak
by 0.22 in HSV brightness (the `rim` value in `variants.json`),
so that a graphite part keeps its outline against the ink, the face, and the servos.

`mise run pixel:pet graphite,feet=yellow` writes a pet in those colors
to `Build/appearances/microduck-<hash>/`, as the customizer site downloads it:
`pet.json`, a PNG spritesheet, and the license notice.
The folder's name is `microduck-` and the first 7 hex digits of the SHA-256 of
`microduck-appearance/1 head=<color> body=<color> beak=<color> feet=<color>`,
as UTF-8 with single spaces and no newline,
so the same colors always make the same folder,
and no pet replaces the packaged `microduck`.
`/Preview/?pets=../Pets,../Build/appearances&only=microduck,microduck-<hash>`
shows it beside the default.

About a tenth of the art's pixels sit where PixelLab's drawing and the part mask disagree,
mostly one or two pixels off a part's edge.
Those pixels take a nearby part,
so a recolored part's edge can be a pixel off the model's.

### Packaging

`Scripts/package.py` takes each pet from the first build that has it,
pixel art before 3D,
checks the atlas against the Codex v2 pet contract,
encodes it as lossless WebP,
and confirms that the WebP decodes to the same pixels.

### Customizer site

`Site/` is a static [Astro](https://astro.build) site
where a visitor colors their own Microduck and downloads it as a pet.
It offers the physical robot's options from `Art/microduck/variants.json` as swatches,
with no free color picker,
and animates each row at the app's timings.
The visitor's name for the pet goes only into `pet.json`'s `displayName`.

The site builds the pet in the browser.
It recolors the palette, packs the atlas,
encodes it as PNG, which the app accepts as well as WebP,
and zips the pet's `microduck-<hash>` folder with `pet.json` and the license notice.
`pixelart.py site-data` writes the art data from `microduck.aseprite` at build time,
so the site and the packaged pet can't drift apart.
It also precomputes every part's colors for every color,
so the site recolors exactly as `pixelart.py pet` does.
The site's tests check the folder encoding, a known folder name, and two atlases
against the command-line tools.

The site deploys as a static Hugging Face Space that serves the built files:
`mise run site:deploy` uploads `Site/dist` with `Site/space/README.md`,
whose front matter sets `sdk: static`.
`Site/space.json` names the Space's owner and name.

## Development

| Directory     | Contents                                                       |
| ------------- | -------------------------------------------------------------- |
| `Sources/`    | The renderer: stage, rigs, choreography, and atlas builder     |
| `Resources/`  | The robot models, copied from Pollen Pet                       |
| `Art/`        | Microduck's sprite, its provenance and colors, and the transfer style reference |
| `Pets/`       | The packaged pets, ready to install                            |
| `Preview/`    | A page that plays every row at the Codex frame timings         |
| `Site/`       | The customizer site, which builds a pet in the visitor's colors     |
| `Scripts/`    | Pixel-art tools, the PixelLab client, packaging, and installation |
| `ThirdParty/` | Model sources and license notices                              |

### Prerequisites

- macOS 15 or later, with a GPU
- Xcode 16 or later
- [mise](https://mise.jdx.dev), which installs [uv](https://docs.astral.sh/uv/), Node.js, and pnpm
- [ShellCheck](https://www.shellcheck.net), for `mise run check`
- [Git LFS](https://git-lfs.com), which stores the robot models in `Resources/Models/` and `Art/microduck/microduck.aseprite`

### Tasks

| Task                       | Effect                                                              |
| -------------------------- | ------------------------------------------------------------------- |
| `mise run setup`           | Build the renderer                                                  |
| `mise run render`          | Render 3D atlases to `Build/render`, and raw frames and part masks to `Build/raw` and `Build/mask` |
| `mise run pixel:inputs`    | Make Microduck's frame-transfer inputs in `Build/transfer`          |
| `mise run pixel:inputs:front` | Render Microduck's in-place rows facing the viewer and make their inputs in `Build/front` |
| `mise run pixel:export`    | Export Microduck's frames and palette from its sprite to `Build/art` and `Build/palette` |
| `mise run pixel:atlas`     | Pack Microduck's sprite into `Build/pixel`                           |
| `mise run pixel:label`     | Give every pixel of Microduck's sprite its part from the part masks |
| `mise run pixel:pet <colors>` | Write a pet in a buyer's colors to `Build/appearances/microduck-<hash>` |
| `mise run pixel:transfer <row>…` and the next steps | Redraw Microduck's rows with PixelLab; see [Redrawing a Microduck row](#redrawing-a-microduck-row) |
| `mise run package`         | Render, pack, and package the pets in `Pets/`                        |
| `mise run check`           | Check the packaged pets and the install script                      |
| `mise run install`         | Copy the packaged pets into the Codex pets folder                   |
| `mise run preview`         | Serve the preview page at `http://127.0.0.1:8000/Preview/`, with the app's timings and loops; set `PORT` for another port |
| `mise run site:dev`        | Serve the customizer site at `http://127.0.0.1:4387/`; set `SITE_PORT` for another port, and press Control-C to stop it |
| `mise run site:build`      | Build the customizer site into `Site/dist`                          |
| `mise run site:check`      | Type-check, lint, and test the customizer site                      |
| `mise run site:deploy`     | Upload the built site to its Hugging Face Space                     |

To render one pet, or to keep each cell as its own image for review:

```bash
mise run render --pet microduck --frames Build/frames
```

The renderer prints the neutral pose's height in the cell
and the frames that touch each edge of the shared fit.
Check those frames if a new pose makes the robot smaller.

### Redrawing a Microduck row

New pixel art costs PixelLab generations,
so these steps aren't part of `mise run package`.
`Scripts/pixellab.py` reads `PIXELLAB_API_TOKEN` from the environment.
Each run writes its frames, a numbered contact sheet,
and a record of its settings and cost to `Build/pixellab/`.
Frame transfer costs 10 generations per call,
and each cleanup call costs 0.1 generations.
The steps marked paid call PixelLab; the others are free.

Each task takes the rows to redraw:
`idle`, `trot`, `waving`, `jumping`, `failed`, `waiting`, `chatter`, `review`,
`look`, and `look-180`.
The trot draws `running-right`, and the left side mirrors it.
`look` draws the looks from 0° to 157.5°, and the other side mirrors them.
A call takes at most 8 frames,
so `look-180` draws 180° and the neutral frame on their own.

1. Change the row in `Choreography.swift`,
   then run `mise run pixel:inputs`.
2. Restyle the row's inputs as pixel art (paid),
   and review each run's contact sheet in `Build/pixellab/`.
   If PixelLab refuses a call as "against policy", run it again.

   ```bash
   mise run pixel:transfer jumping
   ```

3. Collect the run under its atlas labels,
   then clean up the frames, put them on the sprite's palette,
   and write them into the sprite.

   ```bash
   mise run pixel:collect jumping
   mise run pixel:correct jumping   # paid
   mise run pixel:stage jumping
   mise run pixel:reduce jumping    # paid
   mise run pixel:finish
   ```

4. Run `mise run package`, then `mise run preview`
   to check the animation at full speed.
   The ChatGPT app plays idle six times slower than the contract's timings,
   and plays every other row three times before it falls back to idle,
   except the walks, which loop while the pet is dragged.
   The preview does the same.

## License

The code in this project is available under the Apache License, Version 2.0.
See the [LICENSE](LICENSE) file for details.

The bundled models, and the art and spritesheets made from them,
keep the models' licenses:

- The Microduck model is copyright Pollen Robotics,
  from [microduck_rl](https://github.com/pollen-robotics/microduck_rl),
  under CC BY-NC-SA 4.0, which does not permit commercial use.
  This project's Microduck model conversion, pixel art, spritesheets, and recolored pets
  are adaptations of it, licensed under
  [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
  If you share them or adapt them, ShareAlike requires the same license.
- The Reachy Mini model is by Clément Plays for Pollen Robotics,
  from [reachy_mini_blender](https://github.com/pollen-robotics/reachy_mini_blender),
  under the Apache License, Version 2.0.

See [ThirdParty/README.md](ThirdParty/README.md) for sources and details.

## Legal

Microduck and Reachy Mini are products of Pollen Robotics.
Codex and ChatGPT are products of OpenAI.
This project is not affiliated with or endorsed by Pollen Robotics or OpenAI.
