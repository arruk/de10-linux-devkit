#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

export LD_LIBRARY_PATH="$ROOT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DISPLAY=${DISPLAY:-:0.0}
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-x11}
export SDL_AUDIODRIVER=${SDL_AUDIODRIVER:-alsa}

exec "$ROOT_DIR/bin/chocolate-doom" "$@"
