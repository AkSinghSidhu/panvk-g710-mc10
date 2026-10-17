#!/bin/sh
# bootstrap-android-deps.sh — stage the aarch64-Android dependency prefix that
# build-android.sh pins pkg-config to (work/android-deps). Upstream has no
# script for this; without it the cross build either leaks host libraries or
# fails on the libdrm requirement.
#
# Contents:
#   zlib    — .pc shim only: the NDK sysroot provides zlib.h/libz.so, and
#             bionic ships libz.so at runtime (the shipped ICD links it).
#   libdrm  — built from source with the NDK as a STATIC library. Mesa
#             hard-requires libdrm at configure time for this configuration
#             (any Vulkan driver -> with_dri2), and the series keeps
#             runtime-dead DRM call sites compiled in (uses_kbase branches,
#             device enumeration, debug paths), so real drm references reach
#             the link. Static linking keeps the ICD self-contained: no
#             libdrm.so in DT_NEEDED (Android app namespaces cannot load
#             /system/lib64/libdrm.so) — matching the release binary's
#             dependency set (liblog/libnativewindow/libsync/libm/libz).
#
# Usage: ./scripts/bootstrap-android-deps.sh [--api 35] [--out work/android-deps]
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="35"; OUT="$ROOT/work/android-deps"
while [ $# -gt 0 ]; do case "$1" in
    --api) API="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) echo "unknown $1" >&2; exit 2;;
esac; done

if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    for ndk in "$HOME/Android/Sdk/ndk/28.2.13676358" "$HOME/Android/Sdk/ndk" /opt/android-sdk/ndk/28.2.13676358; do
        [ -d "$ndk" ] && { ANDROID_NDK_ROOT="$ndk"; break; }
    done
fi
[ -n "${ANDROID_NDK_ROOT:-}" ] || { echo "set ANDROID_NDK_ROOT (NDK 28.2.13676358 recommended)" >&2; exit 1; }
NDK_BIN="$(ls -d "$ANDROID_NDK_ROOT"/*/toolchains/llvm/prebuilt/linux-x86_64/bin 2>/dev/null | sort -V | tail -n1)"
[ -n "$NDK_BIN" ] || NDK_BIN="$(ls -d "$ANDROID_NDK_ROOT"/toolchains/llvm/prebuilt/linux-x86_64/bin 2>/dev/null | head -n1)"
[ -n "$NDK_BIN" ] || { echo "NDK toolchain not found under $ANDROID_NDK_ROOT" >&2; exit 1; }
PREBUILT="$(dirname "$NDK_BIN")"
SYSROOT="$PREBUILT/sysroot/usr"
export PATH="$NDK_BIN:$PATH"

mkdir -p "$OUT/lib/pkgconfig"

# --- zlib: .pc shim over the NDK sysroot ---
ZVER="$(sed -n 's/^#define ZLIB_VERSION "\(.*\)".*/\1/p' "$SYSROOT/include/zlib.h" 2>/dev/null | head -1)"
[ -n "$ZVER" ] || ZVER=1.3.1
cat > "$OUT/lib/pkgconfig/zlib.pc" <<EOF
prefix=$PREBUILT
includedir=\${prefix}/sysroot/usr/include
libdir=\${prefix}/sysroot/usr/lib/aarch64-linux-android/$API

Name: zlib
Description: zlib shim over the NDK sysroot (bionic ships libz.so at runtime)
Version: $ZVER
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF

# --- libdrm: built from source with the NDK ---
DRM_SRC="$ROOT/work/drm"
if [ ! -d "$DRM_SRC/.git" ]; then
    git clone --depth 1 https://gitlab.freedesktop.org/mesa/drm.git "$DRM_SRC"
fi
DRM_COMMIT="$(git -C "$DRM_SRC" rev-parse HEAD)"
CROSS="$ROOT/work/drm-android.ini"
cat > "$CROSS" <<EOF
[binaries]
c = 'aarch64-linux-android$API-clang'
ar = 'llvm-ar'
strip = 'llvm-strip'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
pkg_config_libdir = []
EOF
rm -rf "$DRM_SRC/build-android"
meson setup "$DRM_SRC/build-android" "$DRM_SRC" --cross-file "$CROSS" \
    --prefix "$OUT" -Dbuildtype=release -Ddefault_library=static \
    -Dc_args=-fvisibility=hidden \
    -Dtests=false -Dinstall-test-programs=false -Dudev=false \
    -Dman-pages=disabled -Dvalgrind=disabled -Dcairo-tests=disabled \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
    -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dtegra=disabled \
    -Dvc4=disabled -Detnaviv=disabled
ninja -C "$DRM_SRC/build-android" install
echo "$DRM_COMMIT" > "$OUT/libdrm-commit.txt"

ls -la "$OUT/lib/pkgconfig"
echo "OK out=$OUT (zlib shim + static libdrm $DRM_COMMIT)"
