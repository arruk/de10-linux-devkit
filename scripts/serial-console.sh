#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Uso:
  serial-console.sh [dispositivo]

Exemplos:
  serial-console.sh
  serial-console.sh /dev/ttyUSB0
EOF
}

if [[ $# -ne 1 ]]; then
	usage
	exit 2
fi

if ! command -v picocom >/dev/null 2>&1; then
	printf 'Erro: instale picocom.\n' >&2
	exit 1
fi

device=$1

if [[ ! -c "$device" ]]; then
    printf 'Porta serial inválida: %s\n' "$device" >&2
    exit 1
fi

printf 'Abrindo %s em 115200 8N1, sem controle de fluxo.\n' "$device"

exec picocom \
	--baud 115200 \
	--databits 8 \
	--parity none \
	--stopbits 1 \
	--flow none \
	"$device"

exit 1
