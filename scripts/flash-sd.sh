#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Uso:
  flash-sd.sh <imagem.img> </dev/disco>

Exemplo:
  flash-sd.sh build/images/de10_standard_lxde.img /dev/sdb

ATENÇÃO: todos os dados do dispositivo serão apagados.
EOF
}

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

required_commands=(
	realpath
	lsblk
	findmnt
	stat
	numfmt
	sha256sum
	sudo
	umount
	dd
	sync
	cmp
	sed
	cut
	head
	xargs
)

for command_name in "${required_commands[@]}"; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'Comando obrigatório ausente: %s\n' "$command_name" >&2
		exit 1
	fi
done

image=$(realpath -- "$1")
device=$(realpath -- "$2")

if [[ ! -f "$image" ]]; then
    printf 'Imagem não encontrada: %s\n' "$image" >&2
    exit 1
fi

if [[ ! -b "$device" ]]; then
    printf 'Não é um dispositivo de bloco: %s\n' "$device" >&2
    exit 1
fi

device_type=$(lsblk --nodeps --noheadings --output TYPE "$device" | xargs)
if [[ "$device_type" != "disk" ]]; then
    printf '%s não é um disco inteiro (tipo detectado: %s).\n' \
        "$device" "$device_type" >&2
    exit 1
fi

if [[ $(lsblk --nodeps --noheadings --output RO "$device" | xargs) == "1" ]]; then
    printf 'O dispositivo está em modo somente leitura: %s\n' "$device" >&2
    exit 1
fi

root_source=$(findmnt --nofsroot --noheadings --output SOURCE --target / | head -n1)
mapfile -t root_devices < <(
    lsblk --inverse --paths --noheadings --output PATH "$root_source" 2>/dev/null
)

for root_device in "${root_devices[@]}"; do
    if [[ "$device" == "$root_device" ]]; then
        printf 'Recusando apagar um disco usado pelo sistema raiz: %s\n' \
            "$device" >&2
        exit 1
    fi
done

image_size=$(stat --format '%s' "$image")
device_size=$(lsblk --bytes --nodeps --noheadings --output SIZE "$device" | xargs)

if (( image_size > device_size )); then
    printf 'A imagem (%d bytes) não cabe no dispositivo (%d bytes).\n' \
        "$image_size" "$device_size" >&2
    exit 1
fi

printf 'Imagem:\n'
printf '  arquivo: %s\n' "$image"
printf '  tamanho: %s\n' "$(numfmt --to=iec-i --suffix=B "$image_size")"
printf '  SHA-256: '
sha256sum -- "$image" | cut -d' ' -f1

printf '\nDispositivo que será TOTALMENTE APAGADO:\n'
lsblk --paths --output NAME,SIZE,TYPE,RM,RO,TRAN,MODEL,SERIAL,MOUNTPOINTS "$device"

expected="APAGAR $device"
printf '\nDigite exatamente "%s" para continuar: ' "$expected"
IFS= read -r confirmation

if [[ "$confirmation" != "$expected" ]]; then
    printf 'Operação cancelada.\n'
    exit 1
fi

sudo -v

while IFS= read -r mountpoint; do
    [[ -n "$mountpoint" ]] || continue
    printf 'Desmontando %s\n' "$mountpoint"
    sudo umount -- "$mountpoint"
done < <(
    lsblk --list --noheadings --output MOUNTPOINTS "$device" |
        sed '/^[[:space:]]*$/d'
)

printf 'Gravando a imagem em %s\n' "$device"
sudo dd \
    if="$image" \
    of="$device" \
    bs=4M \
    iflag=fullblock \
    conv=fsync \
    status=progress

sudo sync

printf 'Verificando os %d bytes gravados\n' "$image_size"
if sudo cmp --silent --bytes="$image_size" "$image" "$device"; then
    printf 'Gravação verificada com sucesso.\n'
else
    printf 'ERRO: o conteúdo gravado não corresponde à imagem.\n' >&2
    exit 1
fi

printf 'Remova o microSD com segurança e siga o checklist da placa.\n'
