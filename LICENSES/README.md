# Licenses in this repository

This tree is **not** uniformly MIT. Do not relicense upstream files.
See `NOTICE.md` for the full picture, including upstream material that is not
part of this slim tree.

| Tree | License | Notes |
|---|---|---|
| Repository scaffolding (`scripts/`, `profiles/`, `docs/`, `worklogs/`, `device/`, packaging) | MIT | `LICENSES/MIT.txt` |
| Mesa sources fetched into `work/mesa/` and Mesa-derived `patches/**/*.patch` | Upstream Mesa (mostly MIT/X11 + Khronos) | Not vendored in git; see Mesa `LICENSES/` after fetch |
| Arm kbase **UAPI headers** committed under `patches/kbase-common/files/` | GPL-2.0 WITH Linux-syscall-note | `LICENSES/GPL-2.0.txt` + `LICENSES/Linux-syscall-note.txt` |
| `kbase_kmod.c` / `kbase_kmod.h` (userspace kmod backend) | MIT | File SPDX; not a UAPI header |
| `leegao/bcn_layer` reference | MIT | Not vendored or packaged; exact text in `LICENSES/bcn_layer-MIT.txt` |

Vendored UAPI headers (GPL-2.0 WITH Linux-syscall-note):

- `patches/kbase-common/files/include/drm-uapi/mali_kbase_ioctl.h`
- `patches/kbase-common/files/src/panfrost/lib/kmod/kbase_uapi.h`
- `patches/kbase-common/files/src/panfrost/lib/kmod/kbase_csf_uapi.h`
- `patches/kbase-common/files/src/panfrost/lib/kmod/mali_kbase_csf_registers.h`
- `patches/kbase-common/files/src/panfrost/lib/kmod/mali_base_kernel.h`
- `patches/kbase-common/files/src/panfrost/lib/kmod/mali_base_common_kernel.h`
- `patches/kbase-common/files/src/panfrost/lib/kmod/mali_base_csf_kernel.h`

The Linux-syscall-note exception is what allows userspace (including MIT Mesa /
this driver) to include those UAPI headers without becoming GPL. It does
**not** relicense the headers themselves. `LICENSES/bcn_layer-MIT.txt` is
retained for reference only — no `bcn_layer` code is present here.

See `NOTICE.md`.
