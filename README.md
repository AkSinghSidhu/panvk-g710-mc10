# PanVK Kbase driver — Mali-G710 MC10 (OnePlus Nord 3 / Dimensity 9000)

Device-specific working tree for our phone only: an open Mesa **PanVK** Vulkan
driver that talks directly to the vendor **`mali_kbase`** kernel interface
(`/dev/mali0`), packaged and documented for the **Mali-G710 MC10**.
Slimmed from [panvk-kbase-android](https://github.com/zenithblue-oss/panvk-kbase-android)
(upstream targets a Mali-G615/Poco X6 Pro; everything G710-irrelevant was removed —
see [What this repo does and does not contain](#what-this-repo-does-and-does-not-contain)).

## Device

| | |
|---|---|
| Phone | OnePlus Nord 3 (CPH2493) |
| SoC | MediaTek Dimensity 9000 (MT6983) |
| GPU | **Mali-G710 MC10** — `Mali-G710 10 cores r0p0 0xA862`, core mask `0x770017` |
| Mesa `PAN_ARCH` | **v10** (Valhall 3rd gen), CSF frontend |
| Kernel | 5.10.246-android12 GKI + MediaTek `mali_kbase_mt6983` |
| `/dev/mali0` | `crw-rw-rw- system graphics`, label `u:object_r:gpu_device:s0` — openable from app UID |
| Android | 16 (SDK 36), OxygenOS; root via KernelSU Next (`adb su`) |
| Driver | `panvk-kbase-v0.1.0-rc3-lowmem` (Mesa 26.3.0-devel `5a07217f`), `.so` BuildID `9d975491`, **minApi 35** (Android 15+) |

Context: G710 sits in Mesa arch **v10** (same family as G310/G510/G610, all CSF).
The upstream fork authors its patch series on **v11** (G615) and relies on runtime
`PAN_ARCH` switches, so the same binary also drives v10 — that is how this phone
runs it. A dedicated `csf-v10` family does not exist yet (see
[Native v10 patch family](#native-v10-patch-family-future-work)).

## Status on this device

Bring-up works: the ICD loads from app storage, device creation succeeds,
Vulkan **1.4.363** (conformance 1.4.1.2), PanProbe 1.2.7 reports
**38 pass / 0 fail / 0 skip**, and the GTA V port boots and renders through it.
It is **not** the port's default driver — the stock ARM blob stays default,
because of the issues below (details, logs and root-cause work:
[docs/G710-MC10-EXPERIMENTS.md](docs/G710-MC10-EXPERIMENTS.md)).

### Known issues on G710

1. **Native BC texture decode (GPU emulation) hangs the GPU.** With the driver's
   BC path active, all three CSF subqueues stop making progress
   (`target − seqno ≈ 44`, stream progress `0x0`), the app freezes and the device
   is lost. Upstream's BC worklog says the path (fragment/compute decode into a
   compressed `bc_shadow` plane + AFRC) was **only validated on G615 (v11)** —
   it has never been exercised on G710 (v10) until us, and it hangs there.
   - Workaround used by the port: **decode BC on the CPU** (`MUGUET_BC_SOFT=1`),
     so no BC image ever reaches the driver.
   - Debug knob: `PANVK_BC_AFRC=0|16|24|32` (0 = exact decode; 16/24/32 force a
     coding-unit size for all formats).
   - Why it matters: native BC keeps textures compressed in GPU memory. Our port
     currently CPU-decodes BC → RGBA8, a 4–8× blow-up that is the main cause of
     the low-memory killer killing the game. Fixing this hang is the big prize.
2. **Timeline/sync wedges.** wgpu-hal + this driver can wedge on timeline waits
   under load; the port uses `MUGUET_NO_TIMELINE=1` (fence-pool path) for PanVK runs.
3. **First-launch shader compile storm.** ~600 pipelines compile on the first
   run (with a compile storm freeze when the disk cache is absent). Set
   `MESA_SHADER_CACHE_DIR` to a persistent directory — the port uses
   `<app files>/mesa-cache` (614 files / 5.3 MB after warm-up).
4. **Performance** is below the stock blob on this SoC today. PanVK remains an
   experiment; blob stays the default.

## Layout

```
profiles/
  g710-v10-csf.json          our device facts (v10 CSF, MT6983, probe results) — target profile
  g615-v11-csf.json          the profile the deployed binary was built with (kept verbatim)
patches/                     CSF build series: common, android, kbase-common, app-loader, wsi, csf, csf-v11
scripts/                     fetch-mesa (pins Mesa 5a07217f) · apply-patches · build-android (NDK) · build-g710 (wrapper) · bootstrap-host-tools · validate-binary · compute-patch-series-id
meson/android-aarch64.ini    Bionic aarch64 cross file used by build-android
sources.lock                 Mesa pin + upstream patch-series id + this tree's trimmed series ids
release/                     the exact binary we deploy + ICD json + sha256s + adpkg provenance (meta/SOURCE/VALIDATION/MANIFEST)
docs/                        ARCHITECTURE · BCN-INTEGRATION · BCN-COMPAT · G710-MC10-EXPERIMENTS (our on-device log)
worklogs/bc-emul-perf/       upstream BC emulation worklog (memory/perf numbers, AFRC knobs)
device/bc-perf*              standalone BC decode/sampling benchmark (needed to debug the G710 BC hang)
```

## Use the prebuilt driver on the phone

The shipped ICD works from app data (no root/system change needed). For the
GTA V port (`com.alihammoud21.gtavmobile`):

```sh
adb push release/libvulkan_panfrost-android-aarch64.so \
  /sdcard/Android/data/com.alihammoud21.gtavmobile/files/vulkan/libvulkan_panfrost.so
adb shell "echo /sdcard/Android/data/com.alihammoud21.gtavmobile/files/vulkan/libvulkan_panfrost.so \
  > /sdcard/Android/data/com.alihammoud21.gtavmobile/files/vk-icd.txt"
# restart the game; the port sets MUGUET_VK_ICD from vk-icd.txt and mini-loads the ICD
```

Recommended env alongside (`files/gpu-env.txt`, one `KEY=VALUE` per line):

```ini
MUGUET_BC_SOFT=1        # decode BC on the CPU (G710: driver BC path hangs)
MUGUET_NO_TIMELINE=1    # avoid timeline-wait wedges under wgpu-hal
```

To go back to the stock blob: delete `files/vk-icd.txt`.

The ICD is proven loadable on this device by PanProbe 1.2.7
("Imported .so"), and by our own port's mini-loader (design in
[docs/G710-MC10-EXPERIMENTS.md](docs/G710-MC10-EXPERIMENTS.md) §"Gate 2").

## Build from source

Prerequisites (this dev machine): NDK `28.2.13676358`
(`~/Android/Sdk/ndk/`), `meson` + `ninja`, host LLVM/clang, `python3`, `git`.

```sh
./scripts/build-g710.sh                 # fetch pinned Mesa -> apply series -> NDK build -> static checks
# or step by step:
./scripts/fetch-mesa.sh                 # shallow clone + detach at sources.lock mesaCommit
./scripts/apply-patches.sh --profile g615-v11-csf
./scripts/build-android.sh --profile g615-v11-csf --api 35
```

Output: `dist/android-<profile>/libvulkan_panfrost.so` (aarch64, bionic,
no X11/glibc deps; checked by `scripts/validate-binary.sh`).

Notes:

- The **deployed binary** was built upstream from the *full* series (173 patches,
  including the JM families `jm-v9`/`jm-v7`) as profile `g615-v11-csf`; its
  provenance is in [release/adpkg/SOURCE.json](release/adpkg/SOURCE.json)
  (`patchSeriesId sha256:37ac82…`). This tree keeps only the **CSF families**
  (144 patches); a rebuild here is expected to be functionally equivalent for
  CSF but **not bit-identical** — this tree's ids:
  `g710-v10-csf` → `sha256:981e5f36…`, `g615-v11-csf` → `sha256:a4d9cd4e…`
  (recorded in `sources.lock` → `slimTree`).
- `--api 35` matches the shipped binary's `minApi`. `--api 29` builds are
  possible but unproven upstream.
- The first build bootstraps host codegen tools (mesa_clc, vtn_bindgen2,
  panfrost_compile) into `build/host-tools*` — needs host LLVM dev packages.

### Native v10 patch family (future work)

The series is authored on v11; v10 rides it through arch switches. The next
driver-side steps are to split a `csf-v10` family (profiles/g610-v10-csf.json
upstream marks the planned v10 slot), arch-gate the BC emulation off for v10
(or fix it), and drop v11-only assumptions. All of that work lands in this repo.

## What this repo does and does not contain

**Kept** (everything that matters for our phone):

- the CSF build series (`patches/csf`, `patches/csf-v11` + shared families),
- our device profile with probe facts, and the profile of the deployed build,
- the exact deployed binary + ICD manifest with checksums and provenance,
- BC-emulation docs/worklog and the `bc-perf` benchmark harness (our open bug),
- the on-device experiment log (`docs/G710-MC10-EXPERIMENTS.md`).

**Removed** (upstream material for other GPUs/devices):

- JM patch families (`jm-v7`, `jm-v7-wip`, `jm-v9`) and other-GPU profiles
  (`g52-v7`, `g57-v9`, `g610-v10`, `g720-v12`),
- other-device docs/build logs/worklogs (Poco X6 Pro, G615 DXVK, G925 NFS, …),
- apps (`apps/panvk-launcher`, `apps/panvk-test`), `tests/`, `validation/`,
  `compatibility/`, `cloud/`, `snapshots/`, matrix tooling,
- the optional `bcn_layer` component (the release declares
  `bcCompatibilityIncluded: false` — it is not part of the deployed binary).

## Provenance & licenses

- Upstream: `zenithblue-oss/panvk-kbase-android`, release
  `panvk-kbase-v0.1.0-rc3-lowmem` (RC3 + `csf-v11/185`, AFRC 8 bpp for BC1 RGB
  and BC7). `CHANGELOG.md` is the upstream record.
- Mesa: `26.3.0-devel` @ `5a07217f034b` (`sources.lock`).
- Shipped files are byte-identical to the upstream release:
  `release/CHECKSUMS.txt` (sha256, verified 2026-10-17).
- Licensing is **mixed** — read [NOTICE.md](NOTICE.md) before redistributing.
  Repository scaffolding is MIT; `patches/**` are Mesa-derived (Mesa's
  licenses); kbase UAPI headers vendored in `patches/kbase-common/files/` are
  `GPL-2.0 WITH Linux-syscall-note`.

## TODO (when we continue driver work)

- [ ] Debug the G710 native-BC hang: run `device/bc-perf.c` here, sweep
      `PANVK_BC_AFRC=0/16/24/32`, then arch-gate or fix the v10 path.
- [ ] Split a `csf-v10` family; move `g710-v10-csf` off the v11 series.
- [ ] Rebuild in this repo and A/B vs the release `.so` on the phone.
- [ ] If driver BC lands: re-test the port's GPU memory (GL mtrack) and the
      low-memory-killer pressure with 4–8× smaller textures.
