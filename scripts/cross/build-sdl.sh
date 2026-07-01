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
readonly SOURCE_DIR="$ROOT_DIR/repos"

if [[ ! -d "$SOURCE_DIR/SDL" ]]; then
	printf 'Fonte ausente: %s\n' "$SOURCE_DIR/SDL" >&2
	exit 1
fi

readonly WORK_DIR="$ROOT_DIR/build/cross/sdl/"
readonly PREFIX="$ROOT_DIR/build/cross/prefix"
readonly SYSROOT="$ROOT_DIR/build/sysroot"

setup_toolchain
x_library=$(find_x11_library)

if [[ -z "$x_library" ]]; then
	printf 'libX11.so nao encontrada no sysroot.\n' >&2
	exit 1
fi

prepare_build_dir
mkdir -p -- "$WORK_DIR" "$PREFIX"
printf '%s\n' "$BUILD_ID" > "$WORK_DIR/.build-id"

cd "$WORK_DIR"
"$SOURCE_DIR/SDL/configure" \
	--host="$TARGET_TRIPLE" \
	--prefix="$PREFIX" \
	--x-includes="$SYSROOT/usr/include" \
	--x-libraries="$x_library" \
	--disable-static \
	--enable-shared \
	--disable-rpath \
	--enable-alsa \
	--disable-alsatest \
	--enable-alsa-shared \
	--disable-oss \
	--disable-jack \
	--disable-esd \
	--disable-pulseaudio \
	--disable-arts \
	--disable-nas \
	--disable-sndio \
	--disable-fusionsound \
	--disable-libsamplerate \
	--disable-video-wayland \
	--disable-video-rpi \
	--enable-video-x11 \
	--enable-x11-shared \
	--disable-video-x11-xcursor \
	--disable-video-x11-xdbe \
	--disable-video-x11-xinerama \
	--disable-video-x11-xinput \
	--disable-video-x11-xrandr \
	--disable-video-x11-scrnsaver \
	--disable-video-x11-xshape \
	--disable-video-x11-vm \
	--disable-video-vivante \
	--disable-video-directfb \
	--disable-video-kmsdrm \
	--disable-video-opengl \
	--disable-video-opengles \
	--disable-video-vulkan \
	--disable-libudev \
	--disable-dbus \
	--disable-ime \
	--disable-ibus \
	--disable-fcitx \
	--disable-hidapi \
	--enable-arm-neon

make -j"$(nproc)"
make install

# Evita que libtool grave o diretorio de build como RUNPATH no SDL_mixer.
rm -f -- "$PREFIX/lib/libSDL2.la"

