#!/bin/bash
# Redraws rows of Microduck's pixel art with PixelLab, one step at a time.
#
#     Scripts/redraw.sh transfer ROW...   PAID: restyle the rows' 3D renders as pixel art
#     Scripts/redraw.sh collect ROW...    collect the newest transfer runs into Build/art
#     Scripts/redraw.sh correct ROW...    PAID: tidy the collected frames, one call per row
#     Scripts/redraw.sh stage ROW...      restore the outline on the newest correct runs
#     Scripts/redraw.sh reduce ROW...     PAID: put the staged frames on the sprite's palette
#     Scripts/redraw.sh finish            write the newest reduce run into the sprite
#
# ROW is one of: idle trot waving jumping failed waiting chatter review look look-180.
# The trot draws running-right; collection mirrors it into running-left.
# The looks draw 000.0 through 157.5; collection mirrors them into 337.5 through 202.5.
# A call takes at most 8 frames at 68 x 68, so 180 degrees and the neutral frame
# are their own row, look-180, with 157.5 beside them.
#
# Run from the repository root. The paid steps read PIXELLAB_API_TOKEN.
# Frame transfer costs 10 generations a call; correct and reduce cost 0.1.
# PixelLab sometimes refuses a call as "against policy" without charging; run it again.
# Each step finds the newest run of its label in Build/pixellab.
set -euo pipefail

INPUTS=Build/transfer/microduck
STAGED=Build/art/microduck
REFERENCE=Art/microduck/style.png
INSTRUCTIONS="Keep each frame's pose and proportions. Match the reference's colors: \
cream-white shell on the head, body, and thighs; dark gray face, neck, and servos; \
orange beak and feet."

# The row's transfer inputs, in order.
inputs() {
  case $1 in
    idle) echo idle-0 idle-1 idle-2 idle-3 idle-4 idle-5 ;;
    trot) echo running-right-0 running-right-1 running-right-2 running-right-3 \
      running-right-4 running-right-5 running-right-6 running-right-7 ;;
    waving) echo waving-0 waving-1 waving-2 waving-3 ;;
    jumping) echo jumping-0 jumping-1 jumping-2 jumping-3 jumping-4 ;;
    failed) echo failed-0 failed-1 failed-2 failed-3 failed-4 failed-5 failed-6 failed-7 ;;
    waiting) echo waiting-0 waiting-1 waiting-2 waiting-3 waiting-4 waiting-5 ;;
    chatter) echo running-0 running-1 running-2 running-3 running-4 running-5 ;;
    review) echo review-0 review-1 review-2 review-3 review-4 review-5 ;;
    look) echo look-000.0 look-022.5 look-045.0 look-067.5 look-090.0 look-112.5 look-135.0 look-157.5 ;;
    look-180) echo look-157.5 look-180.0 neutral ;;
    *) echo "redraw.sh: unknown row '$1'" >&2; exit 1 ;;
  esac
}

# The frames that the row draws: its inputs, except look-180's first, which only fills the call.
drawn() {
  if [ "$1" = look-180 ]; then echo look-180.0 neutral; else inputs "$1"; fi
}

# The newest run folder with this label. Run folders are named <stamp>-<label>.
run() {
  local found
  found=$(find -H Build/pixellab -maxdepth 1 -type d -name "*-$1" 2>/dev/null | sort | tail -n 1)
  if [ -z "$found" ]; then
    echo "redraw.sh: no run labeled $1 in Build/pixellab" >&2
    exit 1
  fi
  echo "$found"
}

step=${1:-}
[ $# -gt 0 ] && shift
if [ "$step" != finish ] && [ $# -eq 0 ]; then
  echo "usage: Scripts/redraw.sh transfer|collect|correct|stage|reduce ROW..., or Scripts/redraw.sh finish" >&2
  exit 1
fi
# Check every row before any paid call. A function's exit inside $(...) wouldn't stop the script.
for row in "$@"; do
  inputs "$row" >/dev/null
done

case $step in
  transfer)
    for row in "$@"; do
      files=()
      for label in $(inputs "$row"); do files+=("$INPUTS/$label.png"); done
      uv run Scripts/pixellab.py transfer --label "microduck-redraw-transfer-$row" \
        --reference "$REFERENCE" --size 68x68 --instructions "$INSTRUCTIONS" "${files[@]}"
    done
    ;;
  collect)
    # Exporting first stages every frame and the palette that `reduce` uses.
    uv run -q Scripts/pixelart.py export --pet microduck
    for row in "$@"; do
      source=$(run "microduck-redraw-transfer-$row")
      read -r -a labels <<<"$(drawn "$row")"
      case $row in
        trot)
          uv run -q Scripts/pixelart.py collect --pet microduck --run "$source" \
            --labels "${labels[@]}" --mirror running-left-{0,1,2,3,4,5,6,7} ;;
        look)
          uv run -q Scripts/pixelart.py collect --pet microduck --run "$source" --labels "${labels[@]}" \
            --mirror - look-337.5 look-315.0 look-292.5 look-270.0 look-247.5 look-225.0 look-202.5 ;;
        look-180)
          uv run -q Scripts/pixelart.py collect --pet microduck --run "$source" \
            --frames 1 2 --labels "${labels[@]}" ;;
        *)
          uv run -q Scripts/pixelart.py collect --pet microduck --run "$source" --labels "${labels[@]}" ;;
      esac
    done
    ;;
  correct)
    for row in "$@"; do
      files=()
      for label in $(drawn "$row"); do files+=("$STAGED/$label.png"); done
      uv run Scripts/pixellab.py correct --label "microduck-redraw-correct-$row" "${files[@]}"
    done
    ;;
  stage)
    runs=()
    for row in "$@"; do
      found=$(run "microduck-redraw-correct-$row")
      runs+=("$found")
    done
    rm -rf Build/tidy/microduck
    uv run Scripts/pixelart.py stage --pet microduck --run "${runs[@]}"
    ;;
  reduce)
    files=()
    for row in "$@"; do
      for label in $(drawn "$row"); do files+=("Build/tidy/microduck/$label.png"); done
    done
    uv run Scripts/pixellab.py reduce --label microduck-redraw-palette \
      --palette Build/palette/microduck.png "${files[@]}"
    ;;
  finish)
    found=$(run microduck-redraw-palette)
    uv run Scripts/pixelart.py finish --pet microduck --run "$found"
    uv run Scripts/pixelart.py atlas --pet microduck
    ;;
  *)
    echo "redraw.sh: unknown step '$step'" >&2
    exit 1
    ;;
esac
