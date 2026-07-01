#!/usr/bin/env bash
set -euo pipefail

for command_name in \
	make nproc find sha256sum
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

if [[ ! -d "$SOURCE_DIR/SDL_mixer" ]]; then
	printf 'Fonte ausente: %s\n' "$SOURCE_DIR/SDL_mixer" >&2
	exit 1
fi

readonly WORK_DIR="$ROOT_DIR/build/cross/sdl-mixer/"
readonly PREFIX="$ROOT_DIR/build/cross/prefix"
readonly SYSROOT="$ROOT_DIR/build/sysroot"

if [[ ! -f "$PREFIX/include/SDL2/SDL.h" || ! -f "$PREFIX/lib/libSDL2.so" ]]; then
	printf 'SDL2 não compilada. Execute build-sdl.sh primeiro.\n' >&2
	exit 1
fi

setup_toolchain

prepare_build_dir
mkdir -p -- "$WORK_DIR" "$PREFIX"
printf '%s\n' "$BUILD_ID" > "$WORK_DIR/.build-id"

cd "$WORK_DIR"
PKG_CONFIG_SYSROOT_DIR= \
	PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
	SDL_CFLAGS="-I$PREFIX/include/SDL2 -D_REENTRANT" \
	SDL_LIBS="-L$PREFIX/lib -lSDL2" \
	"$SOURCE_DIR/SDL_mixer/configure" \
	--host="$TARGET_TRIPLE" \
	--prefix="$PREFIX" \
	--disable-sdltest \
	--disable-static \
	--enable-shared \
	--disable-music-cmd \
	--enable-music-wave \
	--disable-music-mod \
	--enable-music-midi \
	--enable-music-midi-timidity \
	--disable-music-midi-native \
	--disable-music-midi-fluidsynth \
	--disable-music-ogg \
	--disable-music-flac \
	--disable-music-mp3 \
	--disable-music-opus

make -j"$(nproc)"
make install

rm -f -- "$PREFIX/lib/libSDL2_mixer.la"
