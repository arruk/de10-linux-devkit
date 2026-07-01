#!/usr/bin/env bash
set -euo pipefail

readonly TARGET_TRIPLE=arm-linux-gnueabihf
readonly READELF="${TARGET_TRIPLE}-readelf"

for command_name in \
	find cp chmod xargs sed sort tail file grep tar \
	"$READELF"
do
	command -v "$command_name" >/dev/null 2>&1 || {
		printf 'Comando ausente: %s\n' "$command_name" >&2
			exit 1
		}
done

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly SOURCE_DIR="$ROOT_DIR/repos"

readonly WORK_DIR="$ROOT_DIR/build/cross/chocolate-doom/"
readonly PREFIX="$ROOT_DIR/build/cross/prefix"
readonly SYSROOT="$ROOT_DIR/build/sysroot"
readonly DIST_DIR="$ROOT_DIR/dist/chocolate-doom-de10/"

for binary in chocolate-doom chocolate-setup; do
	if [[ ! -x "$WORK_DIR/src/$binary" ]]; then
		printf 'Executável ausente: %s\n' "$WORK_DIR/src/$binary" >&2
		printf 'Execute build-chocolate.sh primeiro.\n' >&2
		exit 1
	fi
done

rm -rf -- "$DIST_DIR"
mkdir -p -- "$DIST_DIR/bin" "$DIST_DIR/lib"

cp -- "$WORK_DIR/src/chocolate-doom" "$DIST_DIR/bin/"
cp -- "$WORK_DIR/src/chocolate-setup" "$DIST_DIR/bin/"

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
