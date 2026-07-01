# DE10-Standard

Este projeto prepara o Linux LXDE da Terasic e compila aplicações ARM para a
DE10-Standard.

## 1. Baixar e extrair a imagem

Baixe **Linux LXDE Desktop (Kernel 4.5)** na página oficial da Terasic:

<https://www.terasic.com.tw/cgi-bin/page/archive.pl?CategoryNo=167&Language=English&No=1081&PartNo=4>

Extraia o arquivo baixado até obter a imagem `.img`.

Baixe também os fontes usados na compilação:

```bash
mkdir -p build/sources

git clone --branch release-2.0.14 \
  https://github.com/libsdl-org/SDL.git build/sources/SDL

git clone --branch release-2.0.4 \
  https://github.com/libsdl-org/SDL_mixer.git build/sources/SDL_mixer

git clone --branch chocolate-doom-3.1.1 \
  https://github.com/chocolate-doom/chocolate-doom.git \
  build/sources/chocolate-doom

git clone https://github.com/libretro/RetroArch.git \
  build/sources/retroarch

git clone https://github.com/libretro/mame2000-libretro.git \
  build/sources/mame2000-libretro
```

## 2. Montar a imagem e preparar o sysroot

Associe a imagem a um dispositivo de loop:

```bash
loop=$(sudo losetup --find --show --partscan /caminho/de10_standard_lxde.img)
lsblk -f "$loop"
```

Identifique a partição Linux, normalmente `${loop}p2`, e monte-a:

```bash
sudo mkdir -p /mnt/de10-rootfs
sudo mount -o ro "${loop}p2" /mnt/de10-rootfs
```

Prepare o sysroot usado na cross-compilação:

```bash
./scripts/sync-sysroot.sh /mnt/de10-rootfs
```

Depois desmonte a imagem:

```bash
sudo umount /mnt/de10-rootfs
sudo losetup -d "$loop"
```

## 3. Gravar o microSD

Identifique o disco do microSD:

```bash
lsblk
```

Grave a imagem usando o disco inteiro, e não uma partição:

```bash
./scripts/flash-sd.sh /caminho/de10_standard_lxde.img /dev/sdX
```

Todos os dados do dispositivo selecionado serão apagados.

## 4. Compilar

Os fontes devem estar em `build/sources/`.

Para compilar e empacotar o Chocolate Doom:

```bash
./scripts/cross/build-sdl.sh
./scripts/cross/build-sdlmixer.sh
./scripts/cross/build-chocolate.sh
./scripts/cross/package-chocolate.sh
```

O pacote será criado em:

```text
dist/chocolate-doom-de10.tar.gz
```

Para compilar o RetroArch:

```bash
./scripts/cross/build-sdl.sh
./scripts/cross/build-mame.sh
./scripts/cross/build-retroarch.sh
```

O `build-mame.sh` gera `mame2000_libretro.so` em
`build/sources/mame2000-libretro/`.

O pacote será criado em:

```text
dist/retroarch-de10.tar.gz
```

## 5. Configurar a placa

Com a DE10-Standard desligada, configure `MSEL[4:0] = 01010` no `SW10`:

| Chave | Posição |
|---|---|
| `SW10.1` (`MSEL0`) | `ON` |
| `SW10.2` (`MSEL1`) | `OFF` |
| `SW10.3` (`MSEL2`) | `ON` |
| `SW10.4` (`MSEL3`) | `OFF` |
| `SW10.5` (`MSEL4`) | `ON` |
| `SW10.6` | indiferente |

Depois:

1. insira o microSD;
2. conecte o monitor VGA;
3. conecte teclado e mouse às portas USB Host;
4. conecte a saída de áudio `LINE OUT`;
5. conecte a porta `UART to USB` ao computador;
6. ligue a placa.

Abra o console serial:

```bash
./scripts/serial-console.sh /dev/ttyUSB0
```

Configuração serial: `115200 8N1`, sem controle de fluxo.

Login padrão:

```text
usuário: root
senha: nenhuma
```
