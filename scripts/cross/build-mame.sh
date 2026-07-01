source scripts/cross/build-common.sh

ROOT_DIR=$PWD
SYSROOT="$ROOT_DIR/build/sysroot"

setup_toolchain

COMPILER_INCLUDE=$("${CROSS_PREFIX}gcc" -print-file-name=include)

MAME_CFLAGS="$TARGET_CFLAGS \
	-fcommon \
	-fno-strict-aliasing \
	-nostdinc \
	-isystem $COMPILER_INCLUDE \
	-isystem $SYSROOT/usr/include/$TARGET_TRIPLE \
	-isystem $SYSROOT/usr/include"

make -C repos/mame2000-libretro clean

make -C repos/mame2000-libretro \
	platform=unix \
	ARM=1 \
	CC="$CC" \
	AR="$AR" \
	CFLAGS="$MAME_CFLAGS" \
	-j"$(nproc)"
