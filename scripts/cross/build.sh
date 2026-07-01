#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

readonly ROOT_DIR="$(cross_root_dir)"
readonly SOURCE_DIR="$ROOT_DIR/build/sources"
readonly WORK_DIR="$ROOT_DIR/build/cross"
readonly PREFIX="$WORK_DIR/prefix"
readonly DIST_DIR="$ROOT_DIR/dist/chocolate-doom-de10"

load_cross_config
require_commands autoreconf file make pkg-config sha256sum tar
if [[ "${CROSS_HOST_CHECKED:-0}" != 1 ]]; then
    "$SCRIPT_DIR/check-host.sh"
fi

load_toolchain

for source_dir in chocolate-doom SDL SDL_mixer; do
    if [[ ! -d "$SOURCE_DIR/$source_dir" ]]; then
        printf 'Fonte ausente: %s\n' "$SOURCE_DIR/$source_dir" >&2
        printf 'Execute scripts/cross/fetch-sources.sh primeiro.\n' >&2
        exit 1
    fi
done

jobs=$(parallel_jobs)

script_hash=$(sha256sum -- "$0" | cut -d' ' -f1)
build_id=$(printf '%s\n' \
    "$TARGET_TRIPLE" "$CC" "$SYSROOT" "$TARGET_CFLAGS" "$script_hash" |
    sha256sum |
    cut -d' ' -f1)

if [[ -f "$WORK_DIR/.build-id" ]]; then
    previous_build_id=$(cat "$WORK_DIR/.build-id")
else
    previous_build_id=
fi

if [[ -d "$WORK_DIR" && "$previous_build_id" != "$build_id" ]]; then
    printf 'Toolchain ou configuracao mudou; limpando artefatos anteriores.\n'
    rm -rf -- "$WORK_DIR"
fi

toolchain_cflags=${CFLAGS:-}
toolchain_cppflags=${CPPFLAGS:-}
toolchain_ldflags=${LDFLAGS:-}
target_pkg_config_libdir=${PKG_CONFIG_LIBDIR:-}

if [[ -z "$YOCTO_SDK_ENV" ]]; then
    compiler_include=$("${CROSS_PREFIX}gcc" -print-file-name=include)
    target_include="$SYSROOT/usr/include/$TARGET_TRIPLE"
    sysroot_library_dirs=()

    [[ -d "$SYSROOT/lib/$TARGET_TRIPLE" ]] &&
        sysroot_library_dirs+=("$SYSROOT/lib/$TARGET_TRIPLE")
    [[ -d "$SYSROOT/usr/lib/$TARGET_TRIPLE" ]] &&
        sysroot_library_dirs+=("$SYSROOT/usr/lib/$TARGET_TRIPLE")

    toolchain_cppflags+=" -nostdinc -isystem $compiler_include"
    [[ -d "$target_include" ]] &&
        toolchain_cppflags+=" -isystem $target_include"
    toolchain_cppflags+=" -isystem $SYSROOT/usr/include"

    for library_dir in "${sysroot_library_dirs[@]}"; do
        toolchain_ldflags+=" -Wl,-rpath-link,$library_dir"
    done
fi

if [[ -z "$target_pkg_config_libdir" ]]; then
    mapfile -t target_pc_dirs < <(
        find "$SYSROOT/usr/lib" "$SYSROOT/usr/share" \
            -maxdepth 3 -type d -name pkgconfig -print 2>/dev/null
    )

    if (( ${#target_pc_dirs[@]} > 0 )); then
        target_pkg_config_libdir=$(IFS=:; printf '%s' "${target_pc_dirs[*]}")
    else
        target_pkg_config_libdir=/nonexistent
    fi
fi

export CFLAGS="$toolchain_cflags $TARGET_CFLAGS"
export CPPFLAGS="$toolchain_cppflags"
export LDFLAGS="$toolchain_ldflags"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$target_pkg_config_libdir"
export PKG_CONFIG_PATH=

mkdir -p -- "$WORK_DIR" "$PREFIX" "$ROOT_DIR/dist"
printf '%s\n' "$build_id" > "$WORK_DIR/.build-id"

x_library=$(
    find "$SYSROOT/lib" "$SYSROOT/usr/lib" \
        -name 'libX11.so' -printf '%h\n' -quit 2>/dev/null
)

if [[ -z "$x_library" ]]; then
    printf 'libX11.so de desenvolvimento nao encontrada no sysroot.\n' >&2
    exit 1
fi

printf '\n[1/4] SDL2\n'
mkdir -p -- "$WORK_DIR/sdl"
(
    cd "$WORK_DIR/sdl"
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
    make -j"$jobs"
    make install
)

# Evita que libtool grave o diretorio de build como RUNPATH no SDL_mixer.
rm -f -- "$PREFIX/lib/libSDL2.la"

printf '\n[2/4] SDL2_mixer\n'
mkdir -p -- "$WORK_DIR/sdl-mixer"
(
    cd "$WORK_DIR/sdl-mixer"
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
    make -j"$jobs"
    make install
)

rm -f -- "$PREFIX/lib/libSDL2_mixer.la"

printf '\n[3/4] Chocolate Doom\n'
if [[ ! -x "$SOURCE_DIR/chocolate-doom/configure" ]]; then
    (
        cd "$SOURCE_DIR/chocolate-doom"
        autoreconf -fi
    )
fi

mkdir -p -- "$WORK_DIR/chocolate-doom"
(
    cd "$WORK_DIR/chocolate-doom"
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
    make -j"$jobs"
)

printf '\n[4/4] Pacote para a placa\n'
rm -rf -- "$DIST_DIR"
mkdir -p -- "$DIST_DIR/bin" "$DIST_DIR/lib"

cp -- "$WORK_DIR/chocolate-doom/src/chocolate-doom" "$DIST_DIR/bin/"
cp -- "$WORK_DIR/chocolate-doom/src/chocolate-setup" "$DIST_DIR/bin/"

find "$PREFIX/lib" -maxdepth 1 \
    \( -name 'libSDL2-2.0.so*' -o -name 'libSDL2_mixer-2.0.so*' \) \
    -exec cp -a -- {} "$DIST_DIR/lib/" \;

cp -- "$ROOT_DIR/target/run-chocolate-doom.sh" "$DIST_DIR/"
cp -- "$ROOT_DIR/target/run-chocolate-setup.sh" "$DIST_DIR/"
cp -- "$SOURCE_DIR/chocolate-doom/COPYING.md" "$DIST_DIR/COPYING.chocolate-doom.md"
cp -- "$SOURCE_DIR/SDL/COPYING.txt" "$DIST_DIR/COPYING.SDL.txt"
cp -- "$SOURCE_DIR/SDL_mixer/COPYING.txt" "$DIST_DIR/COPYING.SDL_mixer.txt"

chmod +x "$DIST_DIR/run-chocolate-doom.sh" "$DIST_DIR/run-chocolate-setup.sh"

target_glibc=$(
    find "$SYSROOT/lib" "$SYSROOT/usr/lib" -name 'libc.so.6' -print -quit |
        xargs "$READELF" --version-info 2>/dev/null |
        sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' |
        sort -Vu |
        tail -1
)

if [[ -z "$target_glibc" ]]; then
    printf 'ERRO: nao foi possivel determinar a versao GLIBC do sysroot.\n' >&2
    exit 1
fi

while IFS= read -r artifact; do
    required_glibc=$(
        "$READELF" --version-info "$artifact" 2>/dev/null |
            sed -n 's/.*Name: GLIBC_\([0-9][0-9.]*\).*/\1/p' |
            sort -Vu |
            tail -1
    )

    if [[ -n "$required_glibc" &&
          "$(printf '%s\n%s\n' "$target_glibc" "$required_glibc" |
              sort -V |
              tail -1)" != "$target_glibc" ]]; then
        printf 'ERRO: %s requer GLIBC_%s; sysroot fornece ate GLIBC_%s.\n' \
            "$artifact" "$required_glibc" "$target_glibc" >&2
        exit 1
    fi
done < <(
    find "$DIST_DIR/bin" "$DIST_DIR/lib" -type f -o -type l |
        while IFS= read -r artifact; do
            file -L "$artifact" | grep -q 'ELF' && printf '%s\n' "$artifact"
        done
)

printf 'Compatibilidade GLIBC validada: ate GLIBC_%s.\n' "$target_glibc"

file "$DIST_DIR/bin/chocolate-doom"
case "$TARGET_TRIPLE" in
    arm*)
        if ! file "$DIST_DIR/bin/chocolate-doom" | grep -q 'ARM'; then
            printf 'ERRO: o executavel produzido nao e ARM.\n' >&2
            exit 1
        fi
        ;;
    *)
        printf 'Aviso: build de teste nao ARM para target %s.\n' "$TARGET_TRIPLE"
        ;;
esac

(
    cd "$ROOT_DIR/dist"
    tar -czf chocolate-doom-de10.tar.gz chocolate-doom-de10
)

printf '\nPacote: %s\n' "$ROOT_DIR/dist/chocolate-doom-de10.tar.gz"
printf 'Pendrive: scripts/cross/deploy-usb.sh <ponto-de-montagem> [doom1.wad]\n'
