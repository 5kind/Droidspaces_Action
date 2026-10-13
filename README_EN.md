[中文](README.md) | **English**

# KernelSU Action

A GitHub Actions workflow that integrates KernelSU (and its forks), SUSFS and the common kernel patches into an Android kernel, and produces a flashable AnyKernel3 package.

Assumes some familiarity with Android kernels.

## Warning :warning:

If you are not the kernel author, please keep KernelSU builds made from someone else's work to yourself rather than redistributing them. It is a matter of respecting their effort.

## Supported kernels

| Kernel | Status |
| --- | --- |
| `4.9` `4.14` `4.19` `5.4` | Non-GKI, fully supported |
| `5.10` `5.15` `6.1` `6.6` `6.12` | GKI source trees, built with `make` |

> This builds a **source-integrated (built-in)** kernel. If all you want is the GKI loadable module (`kernelsu.ko`), use upstream's DDK flow instead.

## Quick start

1. Fork this repository.
2. Edit [`config.env`](config.env) — at minimum `KERNEL_SOURCE`, `KERNEL_SOURCE_BRANCH`, `KERNEL_CONFIG` and `KERNEL_IMAGE_NAME`.
3. Go to `Actions` → `Build Kernel` → `Run workflow`.
4. Pick your KernelSU variant, whether to enable SUSFS, and so on, then run it.
5. Download the AnyKernel3 artifact and flash it from a custom recovery.

The dropdowns all default to `config`, meaning "use whatever the config file says". They **override** the matching key in `config.env` only when you actively change them, so day-to-day tweaking needs no commits — and simply hitting Run always builds exactly what your profile describes, rather than silently switching off a feature you enabled because some checkbox defaulted to off.

To keep one profile per device, copy `config.env` to `config/<device>.env` and pass that path as `Config file to build`.

## Supported KernelSU variants

Selected with `KSU_VARIANT`:

| Value | Project | Notes |
| --- | --- | --- |
| `none` | — | No root solution, plain kernel build |
| `kernelsu` | [tiann/KernelSU](https://github.com/tiann/KernelSU) | The original. **Dropped non-GKI support at v1.0**, so older kernels are pinned to `v0.9.5` automatically |
| `kernelsu-next` | [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | Branches are `dev` (default), `stable`, `legacy`. Use `legacy` for older kernels |
| `sukisu-ultra` | [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | `main` is the modular v4 tree (supports KPM); `builtin` is the source-integrated tree and the **only ref that ships SUSFS itself** |
| `resukisu` | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | A re-fork of SukiSU-Ultra aimed at legacy/non-GKI kernels, with multi-manager support |
| `rsuntk` | [rsuntk/KernelSU](https://github.com/rsuntk/KernelSU) | Also known as RKSU |
| `backslashxx` | [backslashxx/KernelSU](https://github.com/backslashxx/KernelSU) | Manual-hook oriented |

`KSU_REF` takes a branch, tag or commit. **Leave it blank** to let the action pick a sensible ref for your kernel version.

> **Why the ref is validated**
>
> Every variant's `setup.sh` ends its checkout with
> `git checkout "$1" || echo "[-] Checkout default branch"`.
> A ref that does not exist therefore **does not fail** — it quietly leaves you
> on the default branch. Following SukiSU-Ultra's own (stale) docs and passing
> `susfs-main`, a branch that does not exist, gets you a "successful" build
> whose kernel has no SUSFS in it at all.
> This action validates the ref **before** invoking `setup.sh`, and fails with
> the list of branches that do exist.

## SUSFS

Set `ENABLE_SUSFS=true`. Patches come from [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu); the branch is chosen from your kernel version:

| Kernel | SUSFS branch |
| --- | --- |
| 4.9 / 4.14 / 4.19 / 5.4 | `kernel-<version>` |
| 5.10 | `gki-android12-5.10` |
| 5.15 | `gki-android13-5.15` |
| 6.1 | `gki-android14-6.1` |
| 6.6 | `gki-android15-6.6` |
| 6.12 | `gki-android16-6.12` |

Override with `SUSFS_BRANCH` when the guess is wrong (for instance a 5.10 tree that is actually android13-based).

The sequence is: copy `fs/susfs.c` and `include/linux/susfs*.h` → apply the kernel-side `50_add_susfs_in_*.patch` → apply the KernelSU-side `10_enable_susfs_for_ksu.patch`. That last step is **skipped automatically** when the chosen variant already bundles SUSFS (for example SukiSU-Ultra's `builtin`).

The set of `CONFIG_KSU_SUSFS_*` options is read out of the Kconfig that was actually patched in rather than hardcoded, because it differs by branch: the GKI branches ship SUSFS v2.x (which has `SUS_MAP` and has dropped the `AUTO_ADD_*` knobs) while the non-GKI branches are still on v1.5.5 (which is the exact opposite).

> **Known rough edge**: susfs4ksu's non-GKI branches have not been updated since early 2025 and still target KernelSU's old flat source layout. Most forks have since restructured into a modular `kernel/` tree, so the KernelSU-side patch can fail for "old kernel + modern fork + SUSFS". The simplest fix is `KSU_VARIANT=sukisu-ultra` with `KSU_REF=builtin`, which bundles SUSFS and does not need that patch. The build prints this advice when it hits the case.

## path_umount

`path_umount()` only arrived in Linux 5.9. KernelSU uses it to unmount its own mounts before an app checks for root, so older kernels need it backported or module unmounting silently does nothing.

Set `ENABLE_PATH_UMOUNT=true`. The code is upstream's, inserted into `fs/namespace.c` after `do_umount()`. It is skipped automatically on 5.9+ and on trees that already have the function.

## Other patches

| Option | Effect |
| --- | --- |
| `ENABLE_HIDE_STUFF` | Extra removal of KernelSU traces |
| `ENABLE_KPM` | SukiSU-Ultra's Kernel Patch Module support; runs `patch_linux` against the built Image. `sukisu-ultra` + `arm64` only |
| `KSU_HOOK_MODE` | `auto` (kprobes on 5.10+, manual below) / `kprobes` / `manual` / `tracepoint` / `syscall` / `none` |

On older kernels, unreliable kprobes is the usual reason KernelSU installs but `su` does nothing — use `manual` there.

## Toolchains

The AOSP prebuilt clang repository has a trap: every `kernel-build` branch lists **all** version directories, but only one or two actually contain a toolchain. The rest are empty placeholders — and an empty directory still produces a valid tarball that downloads with HTTP 200. So a wrong version does not 404; it fails forty minutes later with `clang: not found`.

Verified working pairs (2026-07):

| `CLANG_BRANCH` | `CLANG_VERSION` |
| --- | --- |
| `main-kernel` | `r596125` (newest) |
| `main-kernel-2026` | `r584948c` |
| `main-kernel-2025` | `r547379` |
| `main-kernel-build-2024` | `r510928` |
| `master-kernel-build-2022` | `r450784e` |

Newer clang often fails to build 4.x trees; use `r450784e` for `4.9`–`4.19` and `r547379` or newer for `5.10+`. The build verifies that `bin/clang` really exists after extraction and warns about pairs outside this table.

Third-party toolchains work too: `USE_CUSTOM_CLANG=true` plus `CUSTOM_CLANG_SOURCE` (a git repo, or a direct zip/tar link).

## Configuration

Every key is documented inline in [`config.env`](config.env). The ones people touch most:

| Option | Meaning |
| --- | --- |
| `KERNEL_IMAGE_NAME` | The kernel binary to flash; matches `BOARD_KERNEL_IMAGE_NAME` in your device tree. Usually `Image.gz-dtb`, `Image.gz` or `Image` |
| `EXTRA_CMDS` / `CUSTOM_CMDS` | Appended to every `make`; values may contain `=` |
| `USE_LLVM` | Full LLVM build (`LLVM=1 LLVM_IAS=1`), suitable for 5.10+ |
| `ADD_OVERLAYFS_CONFIG` | Needed for KernelSU modules and system read-write |
| `DISABLE_LTO` | LTO optimises the kernel but sometimes breaks the build |
| `DISABLE_CC_WERROR` | Fixes kernels that turn KernelSU's warnings into errors |
| `EXTRA_DEFCONFIG` | Arbitrary extra defconfig lines, e.g. `CONFIG_TMPFS_XATTR=y` |
| `BUILD_BOOT_IMG` + `SOURCE_BOOT_IMAGE` | Repack a boot.img; needs a direct link to a bootable image from the same device and ROM |
| `KSU_EXPECTED_SIZE` / `KSU_EXPECTED_HASH` | Custom manager signature, from `ksud debug get-sign <apk>` |

## Backwards compatibility

Existing `config.env` files keep working untouched. These keys are translated automatically, with a notice in the log:

| Old key | New key |
| --- | --- |
| `ENABLE_KERNELSU=true` | `KSU_VARIANT=kernelsu` |
| `KERNELSU_TAG` | `KSU_REF` |
| `APPLY_KSU_PATCH=true` | `KSU_HOOK_MODE=manual` |
| `DISABLE-LTO` | `DISABLE_LTO` |

## Layout

```
.github/workflows/
  build-kernel.yml   build entry point (workflow_dispatch + workflow_call)
  ci.yml             shellcheck / actionlint / config validation / upstream link check
scripts/
  lib.sh             logging, retry, Kconfig read-write, patching, ref validation
  config.sh          config resolution, input overrides, validation
  toolchain.sh       clang / gcc / mkbootimg
  source.sh          kernel source checkout
  kernelsu.sh        variant registry and installation
  patches.sh         SUSFS / path_umount / hide_stuff / hooks / KPM
  build.sh           defconfig injection and compilation
  package.sh         AnyKernel3 / boot.img
patches/
  legacy_ksu_hooks.sh  the original sed-based hook script (fallback for manual mode)
```

`build-kernel.yml` is also reusable via `workflow_call`, so you can keep a very short per-device workflow.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `clang: not found`, or an empty toolchain directory | Invalid `CLANG_BRANCH` / `CLANG_VERSION` pair — see the table above |
| `ref '...' does not exist` | `KSU_REF` names a branch that is not there; the log lists the real ones |
| SUSFS kernel patch fails to apply | `SUSFS_BRANCH` does not match the kernel, or the tree was already modified |
| KernelSU installs but `su` does nothing | Unreliable kprobes on an old kernel — set `KSU_HOOK_MODE=manual` |
| Module mounts cannot be unmounted | Kernels below 5.9 need `ENABLE_PATH_UMOUNT=true` |
| defconfig not found | `KERNEL_CONFIG` is wrong; the log lists the available defconfigs |

## Credits

- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [AOSP](https://android.googlesource.com)
- [KernelSU](https://github.com/tiann/KernelSU)
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU)
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)
- [SukiSU_patch](https://github.com/ShirkNeko/SukiSU_patch)
- [xiaoxindada](https://github.com/xiaoxindada)

# Droidspaces Action

[中文](README.md#droidspaces-action) | **English**

`ENABLE_DROIDSPACES=true` enables [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) kernel patches and configures related kernel options for container runtime environments.

This Action references the [Droidspaces kernel configuration guide](https://github.com/ravindu644/Droidspaces-OSS/blob/v6.6.0/Documentation/Kernel-Configuration.md), attempts to apply the corresponding patches, and enables the kernel configurations required for running containers, including network isolation and firewall-related options. Whether specific features are available still depends on the target kernel version, configuration dependencies, patch compatibility, and the device runtime environment.

To trim features or reduce kernel configuration changes, check `scripts/patches.sh` and confirm that your modifications will not break the runtime dependencies you need.

Make sure you have read the relevant documentation and **know what you are doing**.

> [!TIP]
> 
> If you already have a kernel build environment, you can clone this repository, set the configuration environment variables, and apply the corresponding changes to your existing kernel source tree, for example:
>
> ```bash
> . scripts/config.sh; ENABLE_DROIDSPACES=true ENABLE_CUSTOM_PATCHES=true KERNEL_DIR=/path/to/src bash scripts/patches.sh
> ```
>
> To apply all patches from this repository, run the following commands:
>
> (Note: the stock kernel configuration is applied during the `build.sh` stage.)
>
> ```bash
> . config.env 2>/dev/null; . scripts/config.sh; set +e; export KERNEL_DIR=/path/to/src; bash scripts/kernelsu.sh; KSU_DIR=$KERNEL_DIR/KernelSU bash scripts/patches.sh
> ```

## Supported kernels

| Kernel version | Patch directory | Patches applied |
| --- | --- | --- |
| `3.x`, `4.x` | `non-GKI/` | All patches in the directory |
| `5.x`, `6.1`, `6.6` | `GKI/below-kernel-6.12/` | `SYSVIPC_KABI_PATCH`; for 5.4/5.10 also apply `002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch` |
| `6.12` | `GKI/kernel-6.12/` | All patches in the directory |

> [!CAUTION]
>
> GrapheneOS and SuSFS are not supported when the Droidspaces feature is enabled. Refer to the [Droidspaces Rooting Requirements](https://github.com/ravindu644/Droidspaces-OSS/blob/v6.6.0/README.md#rooting-requirements) for more information.

### Stock kernel configuration

Android devices check whether the kernel configuration matches device compatibility requirements via `/proc/config.gz`. After enabling `ENABLE_STOCKCONFIG`, the build script attempts to use the repository's original kernel configuration as the `IKCONFIG` data source, in order to bypass VINTF kernel configuration checks.

This feature does not disable VINTF checks and does not guarantee that all boot compatibility issues will be resolved.

When this feature is enabled, Actions additionally uploads the actual build configuration `out/.config` as a config artifact. The `Release` packaging step also attempts to compress it to produce `release/config.gz`.

> [!TIP]
> 
> In general, enabling this configuration can fix the `There's an internal problem with your device. Contact your manufacturer for details.` boot error popup; some third-party kernels already include similar functionality.
> 
> When troubleshooting missing kernel features, **prioritize checking the actual build configuration**, and do not judge which options are enabled in the actual kernel based on `/proc/config.gz` or `KERNEL_CONFIG`.

## Custom patches

`ENABLE_CUSTOM_PATCHES=true` attempts to apply `${REPO_ROOT}/patches/*.patch` in sequence, then removes the `-dirty` string from `${KERNEL_DIR}/scripts/setlocalversion`, and executes the script when `${REPO_ROOT}/patches/custom.sh` exists.

> [!WARNING]
> 
> When custom patches or Droidspaces kernel patches fail to apply, the build **will not be terminated**. You need to check the Action logs to confirm whether the patches were applied successfully.
>
> Custom patches are applied before Droidspaces patches. If patches depend on a specific code state or conflict with preceding patches, you must adjust the order yourself and verify the final source. This documentation may be outdated; refer to the actual source code for the current behavior.

Reference patch sources:
- [Droidspaces_Kernel_patch](https://github.com/Goldzxcbug/Droidspaces_Kernel_patch): CVE-UserNS, NTsync, cgroup_limits
- [android-gki-custom](https://github.com/1orz/android-gki-custom/tree/main/patches/android12-5.10): Ignore CRC checks, Overlayfs f2fs fix
- [WildKernels](https://github.com/WildKernels/kernel_patches): common
- [AOSP kernel source](https://android.googlesource.com/kernel/common): `git diff a..b path/to/file`

## Droidspaces configuration options

See [`config.sh`](scripts/config.sh); the most commonly used options:

| Option | Description |
| --- | --- |
| `ENABLE_DROIDSPACES` | Enable Droidspaces kernel patches and configuration |
| `SYSVIPC_KABI_PATCH` | Only effective for kernel versions `5.x`, `6.1`, `6.6`; specifies the sysvipc kABI patch |
| `ENABLE_STOCKCONFIG` | Enable Android stock kernel configuration, bypass VINTF compatibility checks, and package the actual build configuration |
| `ENABLE_CUSTOM_PATCHES` | Enable custom patches and scripts, and remove the `-dirty` string |

## Additional repository structure

If `patches/*.patch` or `patches/custom.sh` does not exist, the corresponding patch or script processing is skipped.

```
patches/
  custom.sh            Custom script; can use all functions and variables from patches.sh
  *.patch              Custom patches
```
