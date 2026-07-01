#!/usr/bin/env bash
set -euo pipefail

validate_sysroot() {
	local root=$1
	local item
	local missing=()

	for item in \
		usr/include/stdio.h \
		usr/include/X11/Xlib.h \
		usr/include/alsa/asoundlib.h
	do
		[[ -e "$root/$item" ]] || missing+=("$item")
	done

	for item in \
		libX11.so libasound.so libc.so libm.so libdl.so \
		crt1.o crti.o crtn.o
	do
		if ! find "$root/lib" "$root/usr/lib" \
			-name "$item" -print -quit 2>/dev/null | grep -q .; then
		missing+=("$item")
		fi
	done

	if (( ${#missing[@]} > 0 )); then
		printf 'Sysroot incompleto:\n' >&2
		printf '  %s\n' "${missing[@]}" >&2
		return 1
	fi
}

for command_name in curl dpkg-deb realpath tar dirname find grep readlink ln rm mv; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'Comando obrigatório ausente: %s\n' "$command_name" >&2
		exit 1
	fi
done

readonly SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
readonly ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly SYSROOT="$ROOT_DIR/build/sysroot"

if [[ $# -ne 1 ]]; then
	cat >&2 <<'EOF'
Uso:
  sync-sysroot.sh <rootfs-local-montado>

Exemplos:
  sync-sysroot.sh /mnt/rootfs

O diretorio deve conter lib, usr/include e usr/lib do Linux ARM.
EOF
	exit 2
fi

source_path=$(realpath -- "$1")

if [[ ! -d "$source_path" ]]; then
	printf 'Rootfs não encontrado: %s\n' "$source_path" >&2
	exit 1
fi

if [[ "$source_path" == "$(realpath -m -- "$SYSROOT")" ]]; then
	printf 'Origem e destino não podem ser iguais.\n' >&2
	exit 1
fi

sysroot_parent=$(dirname -- "$SYSROOT")
sysroot_temp="$sysroot_parent/.sysroot.tmp.$$"
trap 'rm -rf -- "$sysroot_temp"' EXIT

mkdir -p -- "$sysroot_temp"

paths=()
for path in \
	lib \
	usr/lib \
	usr/include \
	usr/local/lib \
	usr/local/include
do
	if [[ -e "$source_path/$path" ]]; then
		paths+=("$path")
	fi
done

if (( ${#paths[@]} == 0 )); then
	printf 'Nenhum diretorio de sysroot encontrado em %s.\n' \
		"$source_path" >&2
	exit 1
fi

printf 'Importando sysroot do rootfs local %s\n' "$source_path"
tar -C "$source_path" -cf - "${paths[@]}" |
	tar -C "$sysroot_temp" --no-same-owner -xf -

readonly ALSA_PACKAGE=/tmp/libasound2-dev_armhf.deb
readonly ALSA_URL="https://ports.ubuntu.com/ubuntu-ports/pool/main/a/alsa-lib/libasound2-dev_1.1.0-0ubuntu1_armhf.deb"

if [[ ! -f "$ALSA_PACKAGE" ]]; then
	curl -L --fail -o "$ALSA_PACKAGE" "$ALSA_URL"
fi

dpkg-deb -x "$ALSA_PACKAGE" "$sysroot_temp"


while IFS= read -r -d '' link_path; do
    link_target=$(readlink -- "$link_path")
    if [[ "$link_target" == /* &&
          ( -e "$sysroot_temp$link_target" ||
            -L "$sysroot_temp$link_target" ) ]]; then
        relative_target=$(
            realpath -m \
                --relative-to="$(dirname -- "$link_path")" \
                "$sysroot_temp$link_target"
        )
        ln -snf -- "$relative_target" "$link_path"
    fi
done < <(find "$sysroot_temp" -type l -print0)

validate_sysroot "$sysroot_temp"

rm -rf -- "$SYSROOT"
mv -- "$sysroot_temp" "$SYSROOT"
trap - EXIT
printf 'Sysroot local preparado em %s\n' "$SYSROOT"
