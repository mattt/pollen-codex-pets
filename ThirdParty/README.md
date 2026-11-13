# Sources and credits

The robot models in `Resources/Models/` are copies of the models in
[Pollen Pet](https://github.com/mattt/PollenPet),
which converts them from Pollen Robotics' own sources.
Pollen Pet's import scripts and README describe each conversion.
The source records here also come from Pollen Pet.

Pollen Robotics does not endorse this project,
and the project makes no claim of affiliation.

## Microduck model

Microduck's geometry and assembly are copyright
[Pollen Robotics](https://pollen-robotics.com/microduck/), from
[microduck_rl at revision 0daab16](https://github.com/pollen-robotics/microduck_rl/tree/0daab160d3fb1c2cbaba16a4a19052f36709dd9e)
(November 10, 2026).
The model in `Resources/Models/microduck/` is converted
from that revision's `.stl` meshes and its MJCF body hierarchy
by [Pollen Pet](https://github.com/mattt/PollenPet)'s `Scripts/import_microduck.py`,
pinned to that revision.
[microduck-sources.json](microduck-sources.json) records the source hashes and changes.

The revision's `LICENSE-MODELS.md`, copied unchanged to
[microduck-LICENSE-MODELS.md](microduck-LICENSE-MODELS.md),
licenses the `.stl` meshes in `src/mjlab_microduck/robot/microduck/assets/`
under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/),
with the copyright held by Pollen Robotics,
and everything else, including the MJCF robot descriptions,
under the Apache License 2.0.
[microduck-LICENSE.txt](microduck-LICENSE.txt) is the revision's `LICENSE` file,
the Apache License 2.0, unchanged.
`LICENSE-MODELS.md` asks anyone who shares the meshes or an adaptation of them
to credit Pollen Robotics with a link to the repository,
link to the license, say what changed,
and license the adaptation under CC BY-NC-SA 4.0.

## Reachy Mini model

The [Reachy Mini](https://pollen-robotics.com/reachy-mini/) visualization model
comes from [Pollen Robotics' Blender repository](https://github.com/pollen-robotics/reachy_mini_blender/tree/bfa02cfee9fde8a1bcca7159921110b1a4a2368e).
Its README credits the 3D model and rig to Clément Plays.
The repository includes an Apache 2.0 license, copied to
[reachy-mini-LICENSE.txt](reachy-mini-LICENSE.txt).
[reachy-mini-sources.json](reachy-mini-sources.json) records the pinned revision,
source hash, and conversion changes.

## Microduck pixel art

Microduck's pixel art in `Art/microduck/` and `Pets/microduck/`
was generated with [PixelLab](https://pixellab.ai).
Frame transfer restyled renderings of the Microduck model
as pixel art, one row at a time.
Each transfer took its style from an earlier PixelLab frame of Microduck,
in a chain that began with a base sprite facing the viewer.
PixelLab drew that sprite from renderings of the model
and the product image of four Microducks
on Pollen Robotics' [Microduck page](https://pollen-robotics.com/microduck/).
The current reference, `Art/microduck/style.png`,
is a finished frame of the walk, `running-right-7`.
The product image and the base sprite are not included in this repository.
`Art/microduck/provenance.json` records the PixelLab jobs
that drew and cleaned up every frame.

## Licenses of the Microduck art

The Microduck art in this repository adapts Pollen Robotics' Microduck model:
the converted model in `Resources/Models/microduck/`,
the pixel art in `Art/microduck/` (the sprite `microduck.aseprite`,
its palette and colors, and `style.png`),
and the spritesheet in `Pets/microduck/` and any spritesheet built from the sprite,
including pets in a buyer's colors.
Their changes from the model are recorded in `microduck-sources.json`,
in the README's description of the pipeline, and in `provenance.json`.

ShareAlike applies to all of them:
this project licenses them under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/),
and anyone who shares them, or anything adapted from them,
must license it under CC BY-NC-SA 4.0 or a later version with the same terms,
credit Pollen Robotics with a link to
[microduck_rl](https://github.com/pollen-robotics/microduck_rl),
link to the license, and say what changed.
NonCommercial also applies to all of them:
commercial use requires permission from Pollen Robotics.

The code that renders and draws the art is not an adaptation of the model,
and remains under the project's Apache License 2.0.

## Colors and outline

The Microduck spritesheet uses Pollen Pet's default "Cream" colors:
a cream shell with an orange beak and feet.
The 3D renders, which include Reachy Mini's spritesheet,
have a 2-pixel outline and a border in Pollen Pet's ink and paper colors.
Microduck's pixel art has a 1-pixel outline in the same ink and no paper border.
These colors are visual approximations, not exact hardware colors.

Upstream recolored many of Microduck's parts in its CAD on September 1, 2026:
the lens ring is now yellow, the face plate and brackets beige, and some servos darker.
The pixel art was drawn from renders in the earlier colors,
so the renderer paints those parts in their colors at revision
[1e79c29](https://github.com/pollen-robotics/microduck_rl/tree/1e79c29c97d8b38aee9eefde77a545860ba7658e),
listed in `Sources/RenderPets/PetStage.swift`.
