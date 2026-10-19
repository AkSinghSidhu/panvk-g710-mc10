#!/bin/sh
# build-g710.sh — rebuild the driver for the Mali-G710 MC10 from scratch:
# fetch the pinned Mesa commit, apply the qualified patch series, cross-build
# the Bionic arm64-v8a ICD with the Android NDK.
#
# Usage: ./scripts/build-g710.sh
#   PROFILE=g710-v10-csf   build profile (default; the only profile in this tree)
#   API=35                 Android API level (default 35; the shipped .so is
#                          minApi 35)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-g710-v10-csf}"
API="${API:-35}"

if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    for ndk in "$HOME/Android/Sdk/ndk/28.2.13676358" "$HOME/Android/Sdk/ndk" /opt/android-sdk/ndk/28.2.13676358; do
        [ -d "$ndk" ] && { ANDROID_NDK_ROOT="$ndk"; break; }
    done
fi
if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    echo "set ANDROID_NDK_ROOT (NDK 28.2.13676358 recommended)" >&2
    exit 1
fi
export ANDROID_NDK_ROOT

# Host LLVMSPIRVLib is required by the native mesa_clc build (Mesa with_clc).
# If it is not installed system-wide, use a local extraction of the distro
# package (e.g. `spirv-llvm-translator`, extracted under
# ~/.local/spirv-llvm-translator — override with LLVMSPIRV_PREFIX):
#   tar --zstd -x -C ~/.local/spirv-llvm-translator <pkg.tar.zst>
#   sed -i "s|^prefix=/usr|prefix=$HOME/.local/spirv-llvm-translator/usr|" \
#     ~/.local/spirv-llvm-translator/usr/lib/pkgconfig/LLVMSPIRVLib.pc
SPV="${LLVMSPIRV_PREFIX:-$HOME/.local/spirv-llvm-translator}/usr"
if ! pkg-config --exists LLVMSPIRVLib 2>/dev/null && [ -d "$SPV/lib/pkgconfig" ]; then
    export PKG_CONFIG_PATH="$SPV/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export CMAKE_PREFIX_PATH="$SPV:${CMAKE_PREFIX_PATH:-}"
    export LD_LIBRARY_PATH="$SPV/lib:${LD_LIBRARY_PATH:-}"
    echo "build-g710: using local LLVMSPIRVLib from $SPV"
fi

# fetch-mesa.sh resets the tree to the pinned commit, so re-running the whole
# chain is safe (patch application is not idempotent by itself).
"$ROOT/scripts/fetch-mesa.sh"
"$ROOT/scripts/apply-patches.sh" --profile "$PROFILE"
"$ROOT/scripts/build-android.sh" --profile "$PROFILE" --api "$API"

SO="$ROOT/dist/android-$PROFILE/libvulkan_panfrost.so"
"$ROOT/scripts/validate-binary.sh" --abi android "$SO"
echo "OK $SO"
