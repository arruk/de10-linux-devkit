#!/usr/bin/env bash
set -euo pipefail

for command_name in \
	make nproc find sha256sum autoreconf
do
	command -v "$command_name" >/dev/null 2>&1 || {
		printf 'Comando ausente: %s\n' "$command_name" >&2
			exit 1
		}
done

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-common.sh"

readonly ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly SOURCE_DIR="$ROOT_DIR/build/sources"

if [[ ! -d "$SOURCE_DIR/chocolate-doom" ]]; then
	printf 'Fonte ausente: %s\n' "$SOURCE_DIR/chocolate-doom" >&2
	exit 1
fi

readonly WORK_DIR="$ROOT_DIR/build/cross/chocolate-doom/"
readonly PREFIX="$ROOT_DIR/build/cross/prefix"
readonly SYSROOT="$ROOT_DIR/build/sysroot"

if [[ ! -f "$PREFIX/include/SDL2/SDL.h" || ! -f "$PREFIX/lib/libSDL2.so" ]]; then
	printf 'SDL2 não compilada. Execute build-sdl.sh primeiro.\n' >&2
	exit 1
fi

if [[ ! -f "$PREFIX/include/SDL2/SDL_mixer.h" || ! -f "$PREFIX/lib/libSDL2_mixer.so" ]]; then
	printf 'SDL2_mixer não compilada. Execute build-sdlmixer.sh primeiro.\n' >&2
	exit 1
fi

setup_toolchain

prepare_build_dir
mkdir -p -- "$WORK_DIR" "$PREFIX"
printf '%s\n' "$BUILD_ID" > "$WORK_DIR/.build-id"

if [[ ! -x "$SOURCE_DIR/chocolate-doom/configure" ]]; then
    (
        cd "$SOURCE_DIR/chocolate-doom"
        autoreconf -fi
    )
fi

cd "$WORK_DIR"
SDL_CFLAGS="-I$PREFIX/include/SDL2 -D_REENTRANT" \
SDL_LIBS="-L$PREFIX/lib -lSDL2" \
SDLMIXER_CFLAGS="-I$PREFIX/include/SDL2" \
SDLMIXER_LIBS="-L$PREFIX/lib -lSDL2_mixer" \
"$SOURCE_DIR/chocolate-doom/configure" \
	--host="$TARGET_TRIPLE" \
	--prefix="$PREFIX" \
	--disable-sdl2net \
	--without-libsamplerate \
	--without-libpng \
	--without-fluidsynth \
	--disable-doc \
	--disable-fonts \
	--disable-icons \
	--disable-bash-completion


make -j"$(nproc)"
