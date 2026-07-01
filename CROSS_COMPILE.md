# Cross-compilação para a DE10-Standard

Este fluxo compila no host x86_64 e executa no ARM Cortex-A9 da
DE10-Standard:

```text
Host x86_64
  -> cross-compiler ARM hard-float
  -> sysroot local do Linux LXDE
  -> SDL2 + SDL2_mixer + Chocolate Doom
  -> pacote .tar.gz no pendrive
  -> HPS ARMv7 da DE10-Standard
```

O pacote gerado contém SDL2 e SDL2_mixer privadas. X11, ALSA, `glibc` e
demais componentes básicos continuam vindo do BSP LXDE da placa.
Nenhuma etapa do fluxo principal conecta à placa por SSH.

## Versões fixadas

| Componente | Versão |
|---|---|
| Chocolate Doom | `3.1.1` |
| SDL | `2.0.14` |
| SDL_mixer | `2.0.4` |

Os scripts também conferem os commits correspondentes às tags oficiais.
SDL2_net, FluidSynth, libpng e libsamplerate ficam desabilitados para reduzir
as dependências. SDL_mixer mantém efeitos sonoros, WAVE e MIDI Timidity.

## 1. Preparar o host

Em Debian/Ubuntu:

```bash
sudo apt install \
  autoconf automake libtool pkg-config make git file \
  gcc-arm-linux-gnueabihf
```

Use a toolchain Debian junto com o sysroot exato da imagem LXDE da placa.

## 2. Configurar o cross-compile

```bash
cp config/cross.env.example config/cross.env
```

`config/cross.env` não é versionado.

Há duas opções locais para fornecer headers e bibliotecas ARM:

1. Sysroot já fornecido pelo cross-compiler. Com `SYSROOT=` vazio, os
   scripts consultam automaticamente:

```bash
arm-linux-gnueabihf-gcc -print-sysroot
```

2. Rootfs ARM disponível localmente, por exemplo a partição Linux do
   microSD montada no computador:

```bash
./scripts/cross/sync-sysroot.sh /media/$USER/rootfs
```

Se não quiser remover o microSD, gere o arquivo diretamente na DE10. Com o
pendrive montado na placa em `/media/usb`, execute:

```sh
set -- lib usr/lib usr/include
[ -e /usr/local/lib ] && set -- "$@" usr/local/lib
[ -e /usr/local/include ] && set -- "$@" usr/local/include
tar -C / -czf /media/usb/de10-sysroot.tar.gz "$@"
sync
```

No computador, importe o arquivo trazido pelo pendrive:

```bash
./scripts/cross/sync-sysroot.sh \
  /run/media/$USER/PENDRIVE/de10-sysroot.tar.gz
```

O sysroot importado fica em `build/sysroot` e é validado automaticamente.
Também é possível definir outro caminho em `SYSROOT`.

Uma imagem runtime frequentemente possui bibliotecas, mas não headers e
links de desenvolvimento. Se a validação do rootfs falhar, use uma imagem
ou rootfs que contenha os arquivos de desenvolvimento esperados.

## 3. Compilar

Inicialize os submodules e compile o pacote:

```bash
git submodule update --init --recursive
./scripts/cross/build-sdl.sh
./scripts/cross/build-sdlmixer.sh
./scripts/cross/build-chocolate.sh
./scripts/cross/package-chocolate.sh
```

Os resultados do Chocolate Doom são:

```text
dist/chocolate-doom-de10/
dist/chocolate-doom-de10.tar.gz
```

Para descartar artefatos de compilação, remova os diretórios gerados em
`build/cross/` e `dist/`.

Estrutura do pacote:

```text
chocolate-doom-de10/
  bin/chocolate-doom
  bin/chocolate-setup
  lib/libSDL2-2.0.so.0
  lib/libSDL2_mixer-2.0.so.0
  run-chocolate-doom.sh
  run-chocolate-setup.sh
```

O launcher configura:

```text
DISPLAY=:0.0
SDL_VIDEODRIVER=x11
SDL_AUDIODRIVER=alsa
LD_LIBRARY_PATH=<pacote>/lib
```

## 4. Enviar por pendrive

No host, copie o pacote gerado para o pendrive montado:

```bash
cp dist/chocolate-doom-de10.tar.gz /media/$USER/PENDRIVE/
sync
```

Na placa:

```bash
mkdir -p /home/root
tar -C /home/root -xzf /caminho/do/pendrive/chocolate-doom-de10.tar.gz
cd /home/root/chocolate-doom-de10
./run-chocolate-doom.sh -iwad /caminho/do/pendrive/doom1.wad
```

O arquivo `.tar.gz` preserva permissões executáveis e links simbólicos mesmo
quando a mídia usa FAT ou exFAT.

## Diagnóstico na placa

```bash
cd /home/root/chocolate-doom-de10
file bin/chocolate-doom
LD_LIBRARY_PATH="$PWD/lib" ldd bin/chocolate-doom
echo "$DISPLAY"
cat /proc/fb
aplay -l
```

O `file` deve indicar `ELF 32-bit`, `ARM` e `EABI5`. Se `ldd` reportar uma
biblioteca ausente, ela deve vir do mesmo BSP usado no sysroot.

O IWAD não é baixado ou incluído pelos scripts.

## RetroArch e MAME 2000

Para jogos arcade antigos, os fontes esperados são:

```text
repos/RetroArch/
repos/mame2000-libretro/
```

O core `mame2000_libretro.so` deve ser compilado para ARM usando somente os
headers do sysroot do BSP. Depois, compile e empacote o frontend:

```bash
./scripts/cross/build-retroarch.sh
```

O script configura uma versão reduzida do RetroArch com SDL2, ALSA, NEON e
carregamento dinâmico de cores. OpenGL, rede, menu, shaders e dependências
desnecessárias ficam desabilitados. Ele também impede que headers modernos do
host introduzam símbolos `time64`, incompatíveis com a `glibc 2.23` do BSP.

O resultado fica em:

```text
dist/retroarch-de10/
dist/retroarch-de10.tar.gz
```

Copie uma ROM compatível com o romset MAME 0.37b5 para `roms/`. Na placa:

```bash
tar -xzf retroarch-de10.tar.gz
cd retroarch-de10
./run-retroarch.sh roms/centiped.zip
```
