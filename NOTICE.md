# NOTICE

This repository (`panvk-g710-mc10`) is a **slim, device-specific subset** of
[`panvk-kbase-android`](https://github.com/zenithblue-oss/panvk-kbase-android):
material for other GPUs/devices, the launcher apps and the JM patch families
was removed. The tree mixes several license regimes; do not treat it as
single-license MIT, and do not relicense upstream code.

The upstream `NOTICE.md` remains the full record of the upstream project; this
file describes what *this* tree actually contains.

## 1. MIT repository scaffolding

Build/patch/packaging scripts, `profiles/`, `docs/`, `worklogs/`, `device/`
and the notes added for this tree are MIT-licensed unless a file header states
otherwise. See `LICENSES/MIT.txt` (copyright 2026 panvk-kbase-android
contributors). Modifications made in this slim tree are added under the same
MIT terms.

## 2. Mesa upstream (not vendored)

All Mesa source is fetched by `scripts/fetch-mesa.sh` and stays under Mesa's
upstream licenses (predominantly MIT/X11 with Khronos SGI/X11 portions — see
the Mesa checkout's `LICENSES/` after fetch). `sources.lock` pins the exact
Mesa commit; release manifests (`release/adpkg/SOURCE.json`) record the Mesa
SHA, patch-series hash, compiler, NDK and build host for the shipped binary.

`patches/**/*.patch` are derived modifications of Mesa and keep Mesa's
upstream license. They are not a grant of a new license.

## 3. Linux / Arm kbase UAPI headers — VENDORED

Committed UAPI/register headers under `patches/kbase-common/files/`, SPDX
`GPL-2.0 WITH Linux-syscall-note`:

- `include/drm-uapi/mali_kbase_ioctl.h`
- `src/panfrost/lib/kmod/kbase_uapi.h`
- `src/panfrost/lib/kmod/kbase_csf_uapi.h`
- `src/panfrost/lib/kmod/mali_kbase_csf_registers.h`
- `src/panfrost/lib/kmod/mali_base_kernel.h`
- `src/panfrost/lib/kmod/mali_base_common_kernel.h`
- `src/panfrost/lib/kmod/mali_base_csf_kernel.h`

They are copied into the Mesa build via `patches/*/files/`. The Linux-syscall
exception is the kernel UAPI exception: including these headers from userspace
does not make the driver a derived work of the kernel. The headers themselves
remain GPL-2.0 WITH Linux-syscall-note and are not relicensed here. Copyright
stays with ARM Limited (and other authors named in the file headers). License
texts: `LICENSES/GPL-2.0.txt`, `LICENSES/Linux-syscall-note.txt`.

## 4. Userspace kmod backend (MIT)

- `patches/kbase-common/files/src/panfrost/lib/kmod/kbase_kmod.c`
- `patches/kbase-common/files/src/panfrost/lib/kmod/kbase_kmod.h`

File SPDX is MIT. They implement the pan_kmod backend against the UAPI above;
they are not kernel code and not UAPI headers.

## 5. Reference Kbase work studied by the upstream project (not vendored)

The upstream patch series was written with reference to several Kbase work
projects (wonderkast02/panvk-g720-kbase-csf, leegao/mesa-funnymdzz,
bmdhacks/malisx2 and others). None of their trees are vendored in this
repository; the full list with per-project notes is in the upstream
`NOTICE.md`. Patches kept here retain their upstream header provenance
(purpose / source-reference / tested-GPU / tested-Kbase-UAPI /
Mesa-base-range / dependencies / validation-test).

## 6. BCn compatibility reference (not vendored)

`leegao/bcn_layer` (MIT, © 2025 Pipetto-crypto) is not vendored or packaged;
the exact notice is preserved in `LICENSES/bcn_layer-MIT.txt` for reference.

## 7. Upstream material NOT present in this tree

Compared to upstream, this tree removes, among others:

- the launcher apps, including the vendored Winlator X server (LGPL-2.1,
  `apps/panvk-launcher/...` in upstream),
- the JM patch families (`jm-v7`, `jm-v7-wip`, `jm-v9`),
- other-GPU profiles, other-device docs, tests, validation and cloud tooling.

The corresponding upstream license obligations (e.g. LGPL-2.1 for the Winlator
X server) do not apply to this repository because that code is not part of it.
