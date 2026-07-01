#!/usr/bin/env bash
set -euo pipefail

for command_name in \
	file make patch sed grep find xargs sort tail \
	nproc rm mkdir cp chmod tar \
	arm-linux-gnueabihf-gcc \
	arm-linux-gnueabihf-ar \
	arm-linux-gnueabihf-ranlib \
	arm-linux-gnueabihf-readelf \
	arm-linux-gnueabihf-strip
do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'Comando ausente: %s\n' "$command_name" >&2
		exit 1
	fi
done

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-common.sh"

readonly ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly SOURCE_DIR="$ROOT_DIR/repos/RetroArch"
readonly SDL_PREFIX="$ROOT_DIR/build/cross/prefix"
readonly DIST_DIR="$ROOT_DIR/dist/retroarch-de10"
readonly SYSROOT="$ROOT_DIR/build/sysroot"

setup_toolchain

if [[ ! -x "$SOURCE_DIR/configure" ]]; then
    printf 'Fonte do RetroArch ausente em %s\n' "$SOURCE_DIR" >&2
    exit 1
fi

if [[ ! -f "$SDL_PREFIX/include/SDL2/SDL.h" || ! -f "$SDL_PREFIX/lib/libSDL2.so" ]]; then
    printf 'SDL2 ARM ausente em %s\n' "$SDL_PREFIX" >&2
    exit 1
fi

if [[ ! -f "$SYSROOT/usr/include/alsa/asoundlib.h" ]]; then
    printf 'Headers ALSA ausentes no sysroot: %s\n' "$SYSROOT" >&2
    exit 1
fi

readonly READELF="${CROSS_PREFIX}readelf"
readonly STRIP="${CROSS_PREFIX}strip"

compiler_include=$("${CROSS_PREFIX}gcc" -print-file-name=include)
target_include="$SYSROOT/usr/include/$TARGET_TRIPLE"

renderer_patch="$ROOT_DIR/scripts/cross/patches/retroarch-sdl2-software-renderer.patch"

if [[ ! -f "$renderer_patch" ]]; then
  printf 'Patch ausente: %s\n' "$renderer_patch" >&2
  exit 1
fi

if patch -d "$SOURCE_DIR" -p1 --dry-run --forward \
        < "$renderer_patch" >/dev/null 2>&1; then
    patch -d "$SOURCE_DIR" -p1 --forward < "$renderer_patch"
elif ! patch -d "$SOURCE_DIR" -p1 --dry-run --reverse \
        < "$renderer_patch" >/dev/null 2>&1; then
    printf 'Nao foi possivel aplicar o fallback SDL2 por software.\n' >&2
    exit 1
fi

common_flags="$TARGET_CFLAGS \
	-fcommon \
	-fno-strict-aliasing \
	-nostdinc \
	-isystem $compiler_include"

if [[ -d "$target_include" ]]; then
	common_flags+=" -isystem $target_include"
fi

common_flags+=" -isystem $SYSROOT/usr/include"

link_flags="-static-libgcc -L$SDL_PREFIX/lib"
for library_dir in "$SYSROOT/lib/$TARGET_TRIPLE" \
                   "$SYSROOT/usr/lib/$TARGET_TRIPLE"; do
    [[ -d "$library_dir" ]] &&
        link_flags+=" -Wl,-rpath-link,$library_dir"
done

cd "$SOURCE_DIR"

make clean >/dev/null 2>&1 || true
rm -f -- config.mk config.h config.log

PATH="$SDL_PREFIX/bin:$PATH" \
	PKG_CONFIG_PATH= \
	CC="$CC" \
	CXX="${CXX:-false}" \
	CFLAGS="$common_flags" \
	CXXFLAGS="$common_flags" \
	LDFLAGS="$link_flags" \
	./configure \
	--host="$TARGET_TRIPLE" \
	--prefix=/opt/retroarch-de10 \
	--enable-sdl2 \
	--enable-alsa \
	--enable-dynamic \
	--enable-dylib \
	--enable-threads \
	--enable-neon \
	--enable-floathard \
	--enable-builtinzlib \
	--disable-sdl \
	--disable-menu \
	--disable-x11 \
	--disable-opengl \
	--disable-opengl_core \
	--disable-opengl1 \
	--disable-opengles \
	--disable-egl \
	--disable-vulkan \
	--disable-kms \
	--disable-wayland \
	--disable-networking \
	--disable-netplaydiscovery \
	--disable-networkgamepad \
	--disable-udev \
	--disable-libusb \
	--disable-pulse \
	--disable-pipewire \
	--disable-oss \
	--disable-jack \
	--disable-tinyalsa \
	--disable-ffmpeg \
	--disable-freetype \
	--disable-qt \
	--disable-libretrodb \
	--disable-cheats \
	--disable-cheevos \
	--disable-cheevos_rvz \
	--disable-discord \
	--disable-accessibility \
	--disable-translate \
	--disable-online_updater \
	--disable-update_cores \
	--disable-update_core_info \
	--disable-update_assets \
	--disable-shaderpipeline \
	--disable-glsl \
	--disable-slang \
	--disable-glslang \
	--disable-spirv_cross \
	--disable-crtswitchres \
	--disable-microphone \
	--disable-cdrom \
	--disable-v4l2 \
	--disable-7zip \
	--disable-zstd \
	--disable-chd \
	--disable-flac \
	--disable-runahead \
	--disable-rewind \
	--disable-video_filter \
	--disable-dsp_filter \
	--disable-overlay \
	--disable-imageviewer \
	--disable-audiomixer \
	--disable-bsv_movie \
	--disable-screenshots \
	--disable-langextra \
	--disable-test_drivers

    # O fallback do configure procura estes headers no host. Substitua-os
    # explicitamente pelos headers ARM usados para construir as bibliotecas.
    sed -i \
	    -e "s|-I/usr/include/SDL2|-I$SDL_PREFIX/include/SDL2|g" \
	    -e "s|-I/usr/include/alsa|-I$SYSROOT/usr/include/alsa|g" \
	    -e 's/^HAVE_FONTCONFIG = 1$/HAVE_FONTCONFIG = 0/' \
	    -e '/^FONTCONFIG_CFLAGS = /d' \
	    -e '/^FONTCONFIG_LIBS = /d' \
	    config.mk


    if grep -Eq -- '(^|[[:space:]])-I/usr/include(/|[[:space:]]|$)' config.mk; then
        printf 'ERRO: config.mk ainda referencia headers do host.\n' >&2
        grep -n -- '-I/usr/include' config.mk >&2
        exit 1
    fi

make -C "$SOURCE_DIR" -j"$(nproc)"

retroarch="$SOURCE_DIR/retroarch"
if [[ ! -f "$retroarch" ]]; then
    printf 'Executavel nao foi produzido: %s\n' "$retroarch" >&2
    exit 1
fi

if ! file "$retroarch" | grep -q 'ARM'; then
    printf 'Executavel produzido nao e ARM:\n' >&2
    file "$retroarch" >&2
    exit 1
fi

if "$READELF" -Ws "$retroarch" |
        grep -Eq '__time64|__localtime64|__stat64_time64'; then
    printf 'ERRO: binario referencia a ABI time64 ausente no BSP.\n' >&2
    exit 1
fi

target_glibc=$(
    find "$SYSROOT/lib" "$SYSROOT/usr/lib" -name 'libc.so.6' -print -quit |
        xargs "$READELF" --version-info 2>/dev/null |
        sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' |
        sort -Vu |
        tail -1
)
required_glibc=$(
    "$READELF" --version-info "$retroarch" 2>/dev/null |
        sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' |
        sort -Vu |
        tail -1
)

if [[ -z "$target_glibc" ||
      "$(printf '%s\n%s\n' "$target_glibc" "$required_glibc" |
          sort -V |
          tail -1)" != "$target_glibc" ]]; then
    printf 'ERRO: RetroArch requer GLIBC_%s; BSP fornece GLIBC_%s.\n' \
        "${required_glibc:-desconhecida}" "${target_glibc:-desconhecida}" >&2
    exit 1
fi

rm -rf -- "$DIST_DIR"
mkdir -p -- "$DIST_DIR/bin" "$DIST_DIR/cores" "$DIST_DIR/lib" \
    "$DIST_DIR/roms"

cp -- "$retroarch" "$DIST_DIR/bin/"
cp -a -- "$SDL_PREFIX/lib/libSDL2-2.0.so.0" \
    "$SDL_PREFIX/lib/libSDL2-2.0.so.0.14.0" \
    "$DIST_DIR/lib/"

core="$ROOT_DIR/repos/mame2000-libretro/mame2000_libretro.so"
if [[ ! -f "$core" ]]; then
    printf 'Core MAME 2000 ausente: %s\n' "$core" >&2
    printf 'Compile mame2000-libretro antes de montar o pacote.\n' >&2
    exit 1
fi

if ! file "$core" | grep -q 'ARM'; then
    printf 'Core MAME 2000 nao e ARM:\n' >&2
    file "$core" >&2
    exit 1
fi

if "$READELF" -Ws "$core" |
        grep -Eq '__time64|__localtime64|__stat64_time64'; then
    printf 'ERRO: core MAME 2000 referencia a ABI time64 ausente no BSP.\n' >&2
    exit 1
fi

cp -- "$core" "$DIST_DIR/cores/"

"$STRIP" --strip-unneeded "$DIST_DIR/bin/retroarch"
"$STRIP" --strip-unneeded "$DIST_DIR/cores/mame2000_libretro.so"

cp -- "$ROOT_DIR/target/run-retroarch.sh" "$DIST_DIR/"
cp -- "$ROOT_DIR/target/retroarch-de10.cfg" "$DIST_DIR/"
chmod +x "$DIST_DIR/run-retroarch.sh"

(
    cd "$ROOT_DIR/dist"
    tar -czf retroarch-de10.tar.gz retroarch-de10
)

file "$DIST_DIR/bin/retroarch"
printf 'GLIBC requerida: %s; disponivel no BSP: %s\n' \
    "$required_glibc" "$target_glibc"
printf 'Pacote: %s\n' "$ROOT_DIR/dist/retroarch-de10.tar.gz"
