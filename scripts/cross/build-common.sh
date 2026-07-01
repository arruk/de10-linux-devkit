#!/usr/bin/env bash

prepare_build_dir() {

	command -v sha256sum >/dev/null 2>&1 || {
		printf 'Comando ausente: sha256sum\n' >&2
			exit 1
		}


	local script_hash previous_build_id

	script_hash=$(sha256sum -- "$0" | cut -d' ' -f1)

	BUILD_ID=$(printf '%s\n' \
		"$TARGET_TRIPLE" "$CC" "$SYSROOT" \
		"$CFLAGS" "$CPPFLAGS" "$LDFLAGS" "$script_hash" |
		sha256sum | cut -d' ' -f1)

	previous_build_id=
	[[ -f "$WORK_DIR/.build-id" ]] &&
		previous_build_id=$(<"$WORK_DIR/.build-id")

	if [[ -d "$WORK_DIR" && "$previous_build_id" != "$BUILD_ID" ]]; then
		rm -rf -- "$WORK_DIR"
	fi
}

setup_toolchain(){

	local compiler_include target_include crt_dir command_name
	local -a pkgconfig_dirs

	command -v mapfile >/dev/null 2>&1 || {
		printf 'Comando ausente: mapfile\n' >&2
			exit 1
		}

	if [[ ! -d "$SYSROOT/usr/include" || ! -d "$SYSROOT/usr/lib" ]]; then
		printf 'Sysroot inválido: %s\n' "$SYSROOT" >&2
		exit 1
	fi

	readonly TARGET_TRIPLE=arm-linux-gnueabihf
	readonly CROSS_PREFIX="${TARGET_TRIPLE}-"
	readonly TARGET_CFLAGS="-O2 -pipe -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard"

	for command_name in \
		"${CROSS_PREFIX}gcc" "${CROSS_PREFIX}ar" \
		"${CROSS_PREFIX}ranlib"
	do
		command -v "$command_name" >/dev/null 2>&1 || {
			printf 'Comando ausente: %s\n' "$command_name" >&2
				exit 1
			}
	done

	compiler_include=$("${CROSS_PREFIX}gcc" -print-file-name=include)
	target_include="$SYSROOT/usr/include/$TARGET_TRIPLE"
	crt_dir=$(
		find "$SYSROOT/usr/lib" "$SYSROOT/lib" \
			-name crt1.o -printf '%h\n' -quit
	)

	if [[ -z "$crt_dir" ]]; then
		printf 'crt1.o não encontrado no sysroot: %s\n' "$SYSROOT" >&2
		exit 1
	fi

	export CC="${CROSS_PREFIX}gcc --sysroot=$SYSROOT -B$crt_dir/"
	if command -v "${CROSS_PREFIX}g++" >/dev/null 2>&1; then
		export CXX="${CROSS_PREFIX}g++ --sysroot=$SYSROOT -B$crt_dir/"
	else
		export CXX=false
		export CXXCPP="$CC -E -x c"
	fi
	export AR="${CROSS_PREFIX}ar"
	export RANLIB="${CROSS_PREFIX}ranlib"

	export CFLAGS="${CFLAGS:-} $TARGET_CFLAGS"
	export CPPFLAGS="${CPPFLAGS:-} -nostdinc -isystem $compiler_include"

	if [[ -d "$target_include" ]]; then
	  CPPFLAGS+=" -isystem $target_include"
	fi

	CPPFLAGS+=" -isystem $SYSROOT/usr/include"

	export LDFLAGS="${LDFLAGS:-} \
		-Wl,-rpath-link,$SYSROOT/lib/$TARGET_TRIPLE \
		-Wl,-rpath-link,$SYSROOT/usr/lib/$TARGET_TRIPLE"

	mapfile -t pkgconfig_dirs < <(
		find "$SYSROOT/usr/lib" "$SYSROOT/usr/share" \
			-maxdepth 3 -type d -name pkgconfig 2>/dev/null
		)

	if (( ${#pkgconfig_dirs[@]} > 0 )); then
		export PKG_CONFIG_LIBDIR
		PKG_CONFIG_LIBDIR=$(IFS=:; printf '%s' "${pkgconfig_dirs[*]}")
	else
		export PKG_CONFIG_LIBDIR=/nonexistent
	fi

	export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
	export PKG_CONFIG_PATH=

}

find_x11_library(){
	find "$SYSROOT/lib" "$SYSROOT/usr/lib" \
		-name 'libX11.so' -printf '%h\n' -quit 2>/dev/null

}
