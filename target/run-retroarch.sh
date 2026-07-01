#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

export LD_LIBRARY_PATH="$ROOT_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DISPLAY=${DISPLAY:-:0.0}
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-x11}
export SDL_AUDIODRIVER=${SDL_AUDIODRIVER:-alsa}

if [ "$#" -eq 0 ]; then
    printf 'Uso: %s <rom.zip> [opcoes do RetroArch]\n' "$0" >&2
    exit 2
fi

exec "$ROOT_DIR/bin/retroarch" \
    -v \
    -c "$ROOT_DIR/retroarch-de10.cfg" \
    -L "$ROOT_DIR/cores/mame2000_libretro.so" \
    "$@"
