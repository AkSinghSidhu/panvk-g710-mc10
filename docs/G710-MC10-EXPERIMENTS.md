# PanVK (open Mesa Vulkan) on the OnePlus Nord 3 — experiment log & integration design

> Snapshot copied into `panvk-g710-mc10` on 2026-10-17 from the GTA V port
> workspace. The workspace copy is canonical; update that first, then re-copy.

Project: https://github.com/zenithblue-oss/panvk-kbase-android
Goal: replace the stock ARM Mali Vulkan blob with open Mesa **PanVK** for the GTA V port,
gain Vulkan 1.4 features, and evaluate the GPU-side BC texture decode path.

Driver release used: `panvk-kbase-v0.1.0-rc3-lowmem` (Mesa 26.3.0-devel, git `5a07217f03`).
Repo clone (host): `panvk-kbase-android/` (691 MB, shallow).
Downloads (host): `panvk-downloads/` — verified against the release `SHA256SUMS`:

| file | sha256 |
|---|---|
| `libvulkan_panfrost-android-aarch64.so` (23.7 MB, bionic aarch64 ICD) | `f550a006…2a0a187` |
| `panfrost_icd.aarch64.json` | `f11bf9e5…82d9c14` |
| `PanProbe-v1.2.7.apk` (35.7 MB) | — |

## Device facts (Nord 3, OxygenOS/Android 16)

| | |
|---|---|
| SoC / GPU | Dimensity 9000 (MT6983) / **Mali-G710 MC10** |
| `gpuinfo` (root) | `Mali-G710 10 cores r0p0 0xA862`; core mask `0x770017` (all 10 cores) |
| **PanVK device ID** | ARM `0x13B5` / **`0xA8620004`** — *identical to the tested Pixel 7 G710 row* |
| Kernel | 5.10.246-android12 GKI + MediaTek `mali_kbase_mt6983` / `mali_mgm` / `mali_prot_alloc` |
| Frontend | CSF (`csg_scheduling_period` present) |
| `/dev/mali0` | `crw-rw-rw- system graphics u:object_r:gpu_device:s0` — **app-openable** |
| Root | KernelSU Next (adb `su` works, no prompt) |

## Gate 1 — driver validation: PASS

- `tests/kbase-probe/probe.c` (NDK r28 build) run as shell and root:
  `NODE-EXISTS yes`, `OPEN O_RDONLY/O_RDWR: OK` for **both uids**.
- **PanProbe 1.2.7 on-device: `38 pass / 0 fail / 0 skip`** (auto-uploaded to project cloud).
- Info screen: `Mali-G710 MC10`, driver `panvk (PanVK-kbase RC3-lowmem (Mesa 26.3.0-devel (git-5a07217f03)))`,
  **Vulkan 1.4.363**, conformance 1.4.1.2, Vk 1.3+1.4 core requirements met,
  post-run `PASS · hard 56/56 · soft 32/38`.
- Stock blob for comparison: Vulkan **1.1.177**, driver r32p1.

So: no port needed for the driver; MC7→MC10 is a non-issue; app-UID loading works.

## Gate 2 — integration into the GTA port (design)

The release `.so` is **ICD-style only** (`vk_icdNegotiateLoaderICDInterfaceVersion`,
`vk_icdGetInstanceProcAddr`, `vk_icdGetPhysicalDeviceProcAddr`; no `vkGetInstanceProcAddr`).
Our runtime loads Vulkan via wgpu-hal → ash (`Entry::load()` → system `libvulkan.so.1`).

Chosen approach — **in-process mini-loader in Rust** (matches the repo's own `vulkan-smoke`
pattern, no Khronos loader, no C shim):

1. Vendor `wgpu-hal` 30.0.1 (`vendor/wgpu-hal`, `[patch.crates-io]`, same as `wgpu-core`).
2. In `vulkan/instance.rs::init_with_callback`, when `MUGUET_VK_ICD` is set:
   - `dlopen` the ICD (libloading; it is an ash dependency),
   - call `vk_icdNegotiateLoaderICDInterfaceVersion(5)` (same as `tests/vulkan-smoke/enumerate.c`),
   - build `ash::StaticFn { get_instance_proc_addr: trampoline }` where the trampoline
     forwards `(instance, name)` to the ICD's `vk_icdGetInstanceProcAddr` (NULL instance for globals),
   - `ash::Entry::from_static_fn(...)` instead of `Entry::load()`.
3. Config plumbing: `files/vk-icd.txt` (path to the ICD `.so`) read in `config::setup()`;
   if present, `set_var("MUGUET_VK_ICD", …)` before GPU init. No file → stock driver (default).
4. Deployment: push the `.so` to `files/vulkan/` (app-owned; dlopen of app data works —
   PanProbe "Imported .so" proves it on this device), write `vk-icd.txt`, restart the game.
5. Logging: extend the existing `[wgpu] device ready` line with `driver`/`driver_info`
   so the active driver (`panvk …` vs `mali`) is visible in `runtime.log`.

### Staging

| step | expected |
|---|---|
| boot with PanVK | `[wgpu] device ready: … driver "panvk…"`; watch `validation error:` / `pipeline … failed` / device-lost |
| first frames | PanVK advertises `TEXTURE_COMPRESSION_BC` → runtime uploads BC **natively** (no CPU decode); `MUGUET_BC_SOFT=1` knob added for A/B if artifacts |
| perf A/B | same save/scene, stock vs PanVK, `fps:` log lines; 93 °C thermal cap noted |
| optional phase 3 | `patches/bcn-layer` + `docs/BCN-INTEGRATION.md`: BC1–BC7 decode on GPU (targets v10) |

## Gate 2b — in-game runs & the pipeline-storm device-loss (2026-10-17)

**Run 1** (debug APK from `9d40d00`, wasm cwasm invalidated → one-time recompile):
boot OK (`driver "panvk"`, surface 1386x620 Mailbox, 0 validation errors) → world reached →
fps 16.3 → 31.0 (fine, `pipelines 4`) → world streaming starts →
**`pipelines 213`, 1160 draws waiting on compiles, fps 7.4** → **device lost** within ~3 s:

```
thread 'gpu' panicked at wgpu-30.0.1/src/backend/wgpu_core.rs:1924:30:
Error in Device::poll: Validation Error
Caused by:
  Parent device is lost
```

- GPU thread died → render stalled; engine hang dump (`waits on the GPU worker 17 s`,
  `POSSIBLE STALL … 10225 ms`); audio mixer kept running; process alive → **black screen,
  overlay controls still visible** (user-visible symptom), no engine sounds.
- **Kernel: no kbase/CSF fault, no GPU reset, no page fault.** The `hang_detect HANG_KICK (300)`
  spam + module lists in dmesg are MTK's *app*-hang watcher reacting to the frozen app.
  NB: `dmesg -T` on this kernel is offset ≈ −20 h vs wall clock — correlate timestamps manually.
- **Driver: silent** — no Mesa stderr before the loss (panvk doesn't log a device-lost reason here).

**Root cause (confirmed):** Mesa line at startup:

```
Failed to create /data/.cache for shader cache (Permission denied)---disabling.
```

→ Mesa's shader **disk cache was disabled**, so every launch recompiles all variants at once when
the world streams in ~700 pipelines → compile/creation storm (213 pipelines + 1160 pending draws in
one fps window) → device lost inside the driver (not a GPU hang per kernel).

**Mitigations landed** (same commit as this doc update):

1. `config.rs`: when `vk-icd.txt` is active, create `<files>/mesa-cache` and set
   `MESA_SHADER_CACHE_DIR` (verified: the `.so` honors it) → compiled shaders persist across runs.
2. `gpu.rs`: `MUGUET_PIPE_THREADS` (default 4, **2** in ICD mode) — fewer concurrent pipeline builds.
3. `gpu.rs`: `MUGUET_BC_SOFT=1` forces the CPU BC path (A/B knob for the white-texture question).

**White textures in run 1 (unattributed):** world frames showed mostly-white / some-normal textures
right before the loss — could be (a) texture uploads still in flight during the storm, or
(b) a PanVK BC-emulation issue. Re-test after a stable run; then A/B `MUGUET_BC_SOFT=1`.

**Convergence plan:** the disk cache fills as shaders compile, so even a mid-storm loss makes the
next run lighter; iterate until the world loads without a loss, then measure steady state.

**Run 2** (Mesa cache active, 2 compile threads): boot OK; fps 14.7 → 31.6 → 22.1 with the storm
**surviving** (shaders persisted: 614 files / 5.3 MB in `mesa-cache`), but the **same panic** hit at
the *world-load mega frame* logged as `2899 draws/frame, 57.0 passes/frame` (1 frame @ 0.1 fps):
`Device::poll … Parent device is lost` → gpu thread gone → engine freeze (`DL_BEGIN_DRAW>Wait on
queued frames`). kbase logged **nothing**; the loss is silent.

**Driver-doc reconnaissance** (`panvk-kbase-android/docs`, worklogs):

- This build **emulates BC1–BC7 with GPU compute shaders** (default on; `PANVK_DEBUG=no_bc_emul`
  disables). RC3-**lowmem** stores BC1 RGB / BC7 as AFRC 8 bpp — a *quality/format change that was
  only retested on G615*; v10 (this device) was not re-validated. Prime suspect for run-1's white
  textures.
- `MESA_VK_ABORT_ON_DEVICE_LOSS=1` makes Mesa print the device-lost **reason** before aborting.
- Known device-lost cause per the docs: **tiler heap exhaustion on complex geometry** → tune
  `PANVK_KBASE_HEAP_RENEW_INTERVAL` (per submit batches, default 128) /
  `PANVK_KBASE_HEAP_RENEW_WORK` (default 65536). Our runtime only submits 1.5–3 batches/frame, so
  the 128-batch default renews rarely.
- Perf caveat for the A/B: panvk's Android swapchain is documented as
  `DeviceWaitIdle` + CPU copy per present (no zero-copy scanout yet).

**Env mechanism:** `files/gpu-env.txt` (KEY=VALUE lines) → `set_default` env in `config::setup()`
(commit `aa43132`; storm mitigations `d2b0c67`), so driver knobs are per-run and stay out of code.

**Run 3 (isolation run):** `MUGUET_BC_SOFT=1` (runtime CPU BC decode — driver never sees BC
textures; same path as the blob) + `MESA_VK_ABORT_ON_DEVICE_LOSS=1` +
`PANVK_KBASE_HEAP_RENEW_INTERVAL=16` + `PANVK_KBASE_HEAP_RENEW_WORK=16384`. Result: the app ran
~30 s, world rendered (buildings textured; ground/cars/characters still white — mid-streaming, the
run was cut short), then **freeze at 19:57:24 → SIGABRT at 19:57:26** (`MESA_VK_ABORT_ON_DEVICE_LOSS`
fired; tombstone `signal 6` on thread `gpu`, abort from `libvulkan_panfrost.so`). Mesa logged to
**logcat** (tag `MESA`, not stderr):

```
kbase: timeout on subqueue 0: seqno 7914 … target 7966 … stream progress 0x0, active 0, error 0x0
kbase: timeout snapshot subqueue 0/1/2 …
```

→ all three CSF subqueues frozen, CS idle, **no error flag** — a submit dependency that never
satisfies. This is the driver CHANGELOG's stated known risk: *"Random DeviceLost (subqueue timeout)
… with wait-before-signal timeline usage this can in theory deadlock (not seen in CTS)"*. The heap
renew knobs and BC isolation did **not** prevent it → not the trigger.

Key inference: the **blob is Vulkan 1.1** → wgpu-hal ran binary semaphores + fence pool; **PanVK is
1.4** → wgpu-hal switched to its **timeline-semaphore** path (`private_caps.timeline_semaphores`),
which is exactly PanVK-kbase's fragile area. The white textures in run 3 (ground/cars) appeared
*with* CPU decode and a 30 s run — most likely just not-yet-streamed assets, not BC corruption.

**Run 4 (timeline fix) — RESULT: stability PASS.** vendored-`wgpu-hal` patch, env-gated
`MUGUET_NO_TIMELINE=1`: force `private_caps.timeline_semaphores=false` → `Fence::FencePool` (VkFence
+ binary semaphores — the same submission machinery the blob always used; the submit relay chain in
wgpu-hal is already binary). Everything else identical to run 3. Result: **~5.3 minutes in-world,
zero MESA errors — no subqueue timeout, no device lost, no tombstone** (contrast: run 3 died 30 s
in). Textures fully correct (user-confirmed; run-3's "white" ground/cars were mid-streaming). The
run was ended at 20:05:08 by a **system LOW_MEMORY kill** (`exit-info reason=3`, rss 3.7 GB,
importance=100) — not a driver fault; earlier blob sessions died the same way at ~3.5 GB. Perf
during load/stream: fps samples 13.4 → 31.3 → 23.2 → **4.0** (world-load mega frame, 2182
draws/frame); 15 freeze reports; render thread parked in `DL_BEGIN_DRAW>Wait on queued frames` →
**present/GPU-bound at single-digit fps through the heavy streaming phase** — perf is the next
target.

**Perf reality check + correction (driver docs/changelog):**
- The RUN-PC-GAMES knob table is **stale**: per `worklogs/g615-dxvk/PROGRESS.md`, patch **103**
  (beta.15, in RC3) already made same-queue semaphore waits go **in-ring by default**
  (`PANVK_KBASE_GPU_SEMAPHORE_WAITS=0` *restores* CPU waits). Measured on NFS: the CPU wait cost
  ~21 ms about once per frame; beta.15 went 24 → 38-40 fps, GPU busy ~96 % @ ~1310 MHz.
  → This also **explains run 3's deadlock mechanism**: with GPU waits default-on, a same-queue
  *timeline* wait is emitted as in-ring `SYNC_WAIT64 GREATER seqno-1`; wgpu-hal's
  wait-before-signal timeline pattern waits on a value signaled only by a *later* submit → the ring
  waits forever → subqueue timeout. Run 4's `MUGUET_NO_TIMELINE` removes that pattern (the binary
  relay is signal-before-wait) → stable.
- Remaining documented per-frame cost: Android WSI present = `DeviceWaitIdle` + CPU memcpy
  (patch 016) — no zero-copy scanout in this build.
- rc3-lowmem BC changes (csf-v11/185): BC1 RGB / BC7 stored as AFRC **8 bpp** (≈4× smaller than
  decoded RGBA; quality tradeoff, retested on G615 only). `PANVK_BC_AFRC` (`0` exact /
  `16`/`24`/`32` force rate) exists per the changelog (not in the public env table).

**Blob↔PanVK A/B (same scene, same env `BC_SOFT=1`):** blob run (20:07-20:13, no `vk-icd.txt`):
world frames **10.6 → 9.7 → 10.4 → 9.6 → 8.1 → 6.8 → 5.3 fps** at ~2900-3250 draws/frame; RSS
climbed **0.76 → 3.26 → 3.38 → 3.53 → 3.64 GB** in 30 s steps (~330 MB/30 s through deep
streaming, never plateauing), textures 9536, pipelines 554 → **LOW_MEMORY kill at 3.6 GB rss**
(20:13:05, foreground). PanVK run 4: last window 4.0 fps at 2182 draws/frame, killed at 3.7 GB.
Verdict so far: **in the world-streaming phase both drivers sit at single-digit fps and both die to
LMK at ~3.6 GB** — this phase is dominated by streaming CPU work + memory growth, not by the Vulkan
driver. (NB: this blob run re-compiled the cwasm one-time — the interrupted force-stop of the
previous launch seems to have invalidated it mid-load — so treat its boot times as pessimistic;
the world-frame samples are unaffected.)

**Run 5 (executed 20:16, PanVK + native BC): FAILED — driver GPU hang.** Identical subqueue-timeout
freeze as run 3 (all three CSF subqueues frozen, `target − seqno ≈ 44`, `stream progress 0x0`,
`error 0x0`), but **with `MUGUET_NO_TIMELINE=1` active** — so the trigger was the driver's own BC
path, not wgpu-hal timelines. Crash ~1 min in, before real world frames (fps log ended at
"pipelines 4", 12 draws/frame); abort flag converted the lost device to SIGABRT (tombstone_04;
panvk frames unsymbolized — `setenforce 0` would fix symbolization on a future crash). The driver
repo's BC worklogs say the native-BC path (fragment decode into `bc_shadow` + AFRC) was **only ever
tested on G615**; G710 (our v10) takes the same path and it hangs. Conclusion: **native BC is not
usable on this driver/chip**; `BC_SOFT` (CPU decode) remains the only route for BC content under
PanVK. No texture-memory win available from the driver, and the blob never advertises BC at all.

## The real blocker: the LMK memory wall (both drivers)

Every long run — blob and PanVK alike — ends the same way: `lowmemorykiller` kills the app with
**~3.8 GB RSS + ~2.0 GB swap = ~5.9 GB total demand** while lmkd reports *"low watermark is
breached and thrashing"* / *"swap utilization is high (92% > 90%)"* (it first kills small system
services, then the game). Device is the **8 GB RAM variant** (`MemTotal 7.2 GiB`, zram 5.77 GB);
idle `MemAvailable` is only ~2.3-2.9 GB, so this is a hard physical constraint, not policy.

Instrumented blob run (20:31:55-20:35:22, clean system, `am kill-all` first): demand
2.46 → 4.84 → 5.25 → 5.58 GB in 30 s-ish steps, fps during deep streaming 8.6-11.0 at ~2500-3150
draws/frame, kill at 20:35:21. Game-side telemetry at death:
- `[wasm] mem: malloc arena 2419 MB (in use 2385 MB)` — grew 1532 → 1880 → 2419 MB over the run
  and was ~99 % full at death; `game virtual 347/466 MB`, `resource virtual 733/768 MB` (both at
  their caps).
- Wasm heap is **fixed at 3072 MB** (module declares memory64 shared, min 4912… — actually
  min 49152 pages = 3072 MB, max 262144 = 16 GiB; our runtime caps max to 5 GB, and
  `emscripten_resize_heap` was never called — the heap never grew).
- Runtime-side live wgpu objects at death: buffers 35495, textures 10561, views 3647, bind groups
  4564, pipelines 605 — monotonic growth, no eviction dips observed.

**Run 6/7 (heap-cap test): hypothesis dead.** `MUGUET_HEAP_MAX_MB=4096` (commit `79eec24`;
shim also caps `emscripten_resize_heap` and logs the first report `[host] emscripten_get_heap_max
-> N MB`) changed nothing: the malloc arena still grew 1532 → 2418 MB and death came at the same
point (~4 min, same kill signature, same fps). The game does not size its streaming/caching
budgets from `emscripten_get_heap_max`, so "tell it it's on an 8 GB phone" is not available as a
lever. Run 7 (same config, watched with per-60 s `dumpsys meminfo <pid>`) gave the real
decomposition roughly 20 s before death:

- **GL mtrack (kernel driver GPU memory) 2.98 GB** — grew 1.58 → 2.98 GB in 60 s and is
  non-swappable, resident RAM. This, not the wasm heap, is what breaches the LMK watermark.
- Rust native heap only 161 MB RSS (+521 MB swapped), buffers/views/bind groups counted in
  thousands but texturing dominates. Game-side pool accounting is ~768 MB, so the GPU is holding
  ~4× what the game thinks it allocated.
- Mechanism: the blob driver can't read BC, so every BC texture is CPU-decoded to RGBA8
  (`bc_soft_format`): BC1 (8 B per 4×4) → 4 B/px = **8×**, BC3/BC7 (16 B per 4×4) → **4×**.
  Texture streaming is monotonic, so GPU-resident bytes track total streamed bytes.

**Run 8 (texture-halve test, in flight):** new `MUGUET_TEX_HALVE=<px>` knob: BC-sourced textures
with a side ≥ px and bind == SRV (sampled-only, never RT/DS/UAV) are decoded at *half resolution*
and allocated at half size — mip indices/levels are unchanged, so views/copies/subresource math
keep working unmodified; the whole texture is effectively sampled one mip softer. `bc_decode_half`
averages each 2×2 of decoded source texels. Expected: ~4× less GPU bytes for the big streamed
textures. Build also adds self-reporting: `gpu tex X MB buf Y MB` (recounted from live objects) and
`N MB swap` in the fps line. Test value 512 px, stock blob.

## Risks

- PanProbe tests ≠ GTA V: clip distances, atomics, read_write storage textures, large
  workloads, real WSI — first in-game run may hit driver bugs (hangs → `logcat -s Mali vulkan`).
- Performance may be *worse* than the r32 blob; measure before adopting. Keep the blob default.
- RC3 is a release candidate; pin the exact `.so` and keep SHA256SUMS.
- Kernel side is MediaTek's private `mali_kbase_mt6983`; RC3 works (proven), but a future
  OS update could change the UAPI.

## Phase 3 (only if wanted later)

Build the driver from source (`scripts/build-android.sh`, profile `g610-v10-csf.json` as the
v10 base + `csf-v11/140` G710 model row; Mesa pinned `5a07217f`), then game-specific tweaks
(e.g., BC-on-GPU layer, pipeline cache behavior, WSI timing) are possible without waiting
for upstream releases.
