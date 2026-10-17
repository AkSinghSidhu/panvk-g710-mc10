#!/bin/sh
# build-g710.sh — rebuild the driver for the Mali-G710 MC10 from scratch:
# fetch the pinned Mesa commit, apply the qualified patch series, cross-build
# the Bionic arm64-v8a ICD with the Android NDK.
#
# Usage: ./scripts/build-g710.sh
#   PROFILE=g615-v11-csf   build profile (default; the one the deployed binary
#                          was built with — see README)
#   API=35                 Android API level (default 35; the shipped .so is
#                          minApi 35)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-g615-v11-csf}"
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

# fetch-mesa.sh resets the tree to the pinned commit, so re-running the whole
# chain is safe (patch application is not idempotent by itself).
"$ROOT/scripts/fetch-mesa.sh"
"$ROOT/scripts/apply-patches.sh" --profile "$PROFILE"
"$ROOT/scripts/build-android.sh" --profile "$PROFILE" --api "$API"

SO="$ROOT/dist/android-$PROFILE/libvulkan_panfrost.so"
"$ROOT/scripts/validate-binary.sh" --abi android "$SO"
echo "OK $SO"
