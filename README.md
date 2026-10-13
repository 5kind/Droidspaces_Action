**中文** | [English](README_EN.md)

# KernelSU Action

用 GitHub Actions 为 Android 内核集成 KernelSU（及其各种分支）、SUSFS 与常用补丁，并产出可刷入的 AnyKernel3 包。

需要一定的内核与 Android 基础知识。

## 警告 :warning:

如果你不是内核作者，使用他人的劳动成果构建 KernelSU，请仅供自己使用，不要分享给别人，这是对原作者劳动成果的尊重。

## 支持范围

| 内核版本 | 状态 |
| --- | --- |
| `4.9` `4.14` `4.19` `5.4` | Non-GKI，完整支持 |
| `5.10` `5.15` `6.1` `6.6` `6.12` | GKI 源码树，使用 `make` 构建 |

> 本仓库构建的是**源码内置（built-in）**内核。若你只想要 GKI 的 LKM 模块（`kernelsu.ko`），请直接用上游的 DDK 方案。

## 快速开始

1. Fork 本仓库。
2. 编辑 [`config.env`](config.env)，至少填好 `KERNEL_SOURCE`、`KERNEL_SOURCE_BRANCH`、`KERNEL_CONFIG`、`KERNEL_IMAGE_NAME`。
3. 打开 `Actions` → `Build Kernel` → `Run workflow`。
4. 在弹出的表单里选择 KernelSU 分支、是否启用 SUSFS 等，然后运行。
5. 构建完成后在 Artifacts 下载 AnyKernel3 压缩包，在 Recovery 中刷入。

表单里的下拉框默认都是 `config`，意思是"用配置文件里写的值"。只有你主动改成别的值时，它才会**覆盖** `config.env` 中的同名配置——所以日常调参不需要提交任何改动，而直接点运行也一定是按你配置文件里的设定来构建，不会因为某个开关默认关着就把你配置里开启的功能悄悄关掉。

想给多台设备各留一份配置，就把 `config.env` 复制成 `config/<设备名>.env`，运行时在 `Config file to build` 里填该路径。

## 支持的 KernelSU 分支

用 `KSU_VARIANT` 选择：

| 取值 | 项目 | 说明 |
| --- | --- | --- |
| `none` | — | 不集成 root，纯编译内核 |
| `kernelsu` | [tiann/KernelSU](https://github.com/tiann/KernelSU) | 官方原版。**v1.0 起不再支持 Non-GKI**，旧内核会自动锁定到 `v0.9.5` |
| `kernelsu-next` | [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | 分支为 `dev`（默认）/ `stable` / `legacy`；旧内核请用 `legacy` |
| `sukisu-ultra` | [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | `main` 为 v4 模块化树（支持 KPM）；`builtin` 为源码内置树，且是**唯一自带 SUSFS** 的分支 |
| `resukisu` | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | SukiSU-Ultra 的再分支，主打旧内核/Non-GKI 兼容与多管理器支持 |
| `rsuntk` | [rsuntk/KernelSU](https://github.com/rsuntk/KernelSU) | 即 RKSU |
| `backslashxx` | [backslashxx/KernelSU](https://github.com/backslashxx/KernelSU) | 以手动 hook 为主 |

`KSU_REF` 填分支名、tag 或 commit。**留空**则按你的内核版本自动挑一个合适的引用。

> **为什么必须校验 `KSU_REF`**
>
> 所有分支的 `setup.sh` 结尾都是
> `git checkout "$1" || echo "[-] Checkout default branch"`。
> 也就是说，填一个不存在的分支名**不会报错**，只会悄悄留在默认分支上。
> 比如按旧文档给 SukiSU-Ultra 传 `susfs-main`（该分支实际上并不存在），
> 构建会"成功"，但产出的内核根本没有 SUSFS。
> 本 Action 会在调用 `setup.sh` **之前**校验引用是否存在，不存在就直接失败并列出可用分支。

## SUSFS

`ENABLE_SUSFS=true` 即可。补丁来自 [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)，分支按内核版本自动选择：

| 内核 | SUSFS 分支 |
| --- | --- |
| 4.9 / 4.14 / 4.19 / 5.4 | `kernel-<版本>` |
| 5.10 | `gki-android12-5.10` |
| 5.15 | `gki-android13-5.15` |
| 6.1 | `gki-android14-6.1` |
| 6.6 | `gki-android15-6.6` |
| 6.12 | `gki-android16-6.12` |

自动映射不对时用 `SUSFS_BRANCH` 手动指定（例如你的 5.10 树其实基于 android13）。

流程为：拷贝 `fs/susfs.c` 与 `include/linux/susfs*.h` → 打内核侧 `50_add_susfs_in_*.patch` → 打 KernelSU 侧 `10_enable_susfs_for_ksu.patch`。最后一步在所选分支**自带 SUSFS 时会自动跳过**（例如 SukiSU-Ultra 的 `builtin`）。

> **已知坑**：susfs4ksu 的 Non-GKI 分支自 2025 年初就没再更新，仍然针对 KernelSU 的旧扁平目录结构。而多数分支此后都重构成了模块化的 `kernel/` 目录，因此"旧内核 + 新分支 + SUSFS"这个组合的 KernelSU 侧补丁可能打不上。遇到这种情况，改用 `KSU_VARIANT=sukisu-ultra` + `KSU_REF=builtin`（自带 SUSFS，不需要那个补丁）最省事。构建失败时日志里会直接给出这段提示。

## path_umount

`path_umount()` 是 Linux 5.9 才引入的。KernelSU 靠它在应用检测 root 前卸载自己的挂载，所以更旧的内核需要回移这个函数，否则"卸载模块挂载"会静默失效。

`ENABLE_PATH_UMOUNT=true` 即可，代码直接取自上游，插入到 `fs/namespace.c` 中 `do_umount()` 之后。在 5.9+ 的内核上会自动跳过；已经有该函数时也会跳过。

## 其它补丁

| 选项 | 作用 |
| --- | --- |
| `ENABLE_HIDE_STUFF` | 额外清除内核中的 KernelSU 痕迹 |
| `ENABLE_KPM` | SukiSU-Ultra 的 Kernel Patch Module 支持，编译后对 Image 执行 `patch_linux`。仅 `sukisu-ultra` + `arm64` |
| `KSU_HOOK_MODE` | hook 方式：`auto`（5.10+ 用 kprobes，更旧的用 manual）/ `kprobes` / `manual` / `tracepoint` / `syscall` / `none` |

旧内核上 kprobes 经常是"KernelSU 装上了但 su 没反应"的元凶，此时用 `manual`。

## 工具链

AOSP 的 clang 预编译仓库有个陷阱：每个 `kernel-build` 分支都会列出**所有**版本目录，但其中只有一两个真的有工具链，其余是空占位符——而空目录生成的 tar 包能以 HTTP 200 正常下载，只是解开后是空的。所以版本写错不会 404，只会在几十分钟后报 `clang: not found`。

已验证可用的组合（2026-07）：

| `CLANG_BRANCH` | `CLANG_VERSION` |
| --- | --- |
| `main-kernel` | `r596125`（最新） |
| `main-kernel-2026` | `r584948c` |
| `main-kernel-2025` | `r547379` |
| `main-kernel-build-2024` | `r510928` |
| `master-kernel-build-2022` | `r450784e` |

新版 clang 在 4.x 树上经常编不过，`4.9`–`4.19` 建议用 `r450784e`，`5.10+` 用 `r547379` 或更新。构建脚本会校验解压结果里确实有 `bin/clang`，并对不在上表中的组合发出警告。

也可以用第三方 clang：`USE_CUSTOM_CLANG=true` + `CUSTOM_CLANG_SOURCE`（支持 git 仓库或 zip/tar 直链）。

## 完整配置项

见 [`config.env`](config.env)，每一项都有注释。几个常用的：

| 选项 | 说明 |
| --- | --- |
| `KERNEL_IMAGE_NAME` | 需要刷写的内核二进制名，与设备树里的 `BOARD_KERNEL_IMAGE_NAME` 一致，常见 `Image.gz-dtb` / `Image.gz` / `Image` |
| `EXTRA_CMDS` / `CUSTOM_CMDS` | 追加到每次 `make` 的参数，值里可以带 `=` |
| `USE_LLVM` | 全 LLVM 构建（`LLVM=1 LLVM_IAS=1`），适合 5.10+ |
| `ADD_OVERLAYFS_CONFIG` | 为 KernelSU 模块与 system 读写提供支持 |
| `DISABLE_LTO` | LTO 会优化内核，但有时会导致编译错误 |
| `DISABLE_CC_WERROR` | 修复某些内核把 KernelSU 的告警当错误的问题 |
| `EXTRA_DEFCONFIG` | 任意追加 defconfig 行，如 `CONFIG_TMPFS_XATTR=y` |
| `BUILD_BOOT_IMG` + `SOURCE_BOOT_IMAGE` | 重新打包 boot.img，需要提供同设备同 ROM 的可开机镜像直链 |
| `KSU_EXPECTED_SIZE` / `KSU_EXPECTED_HASH` | 自定义管理器签名，用 `ksud debug get-sign <apk>` 获取 |

## 兼容旧配置

旧版 `config.env` 无需修改即可继续使用，以下键会自动转换并给出提示：

| 旧键 | 新键 |
| --- | --- |
| `ENABLE_KERNELSU=true` | `KSU_VARIANT=kernelsu` |
| `KERNELSU_TAG` | `KSU_REF` |
| `APPLY_KSU_PATCH=true` | `KSU_HOOK_MODE=manual` |
| `DISABLE-LTO` | `DISABLE_LTO` |

## 仓库结构

```
.github/workflows/
  build-kernel.yml   构建入口（workflow_dispatch + workflow_call）
  ci.yml             shellcheck / actionlint / 配置校验 / 上游链接探活
scripts/
  lib.sh             日志、重试、Kconfig 读写、补丁、引用校验等公共函数
  config.sh          配置解析、输入覆盖、校验
  toolchain.sh       clang / gcc / mkbootimg
  source.sh          拉取内核源码
  kernelsu.sh        KernelSU 分支注册表与安装
  patches.sh         SUSFS / path_umount / hide_stuff / hooks / KPM
  build.sh           defconfig 注入与编译
  package.sh         AnyKernel3 / boot.img
patches/
  legacy_ksu_hooks.sh  旧版 sed hook 脚本（manual 模式的兜底）
```

`build-kernel.yml` 也可以被 `workflow_call` 复用，方便你为每台设备写一个极短的工作流。

## 排错

| 现象 | 原因 |
| --- | --- |
| `clang: not found` / 工具链目录是空的 | `CLANG_BRANCH` 与 `CLANG_VERSION` 组合无效，见上表 |
| `ref '...' does not exist` | `KSU_REF` 填了不存在的分支，日志会列出可用分支 |
| SUSFS 内核补丁打不上 | `SUSFS_BRANCH` 与内核版本不匹配，或该树已被改动过 |
| KernelSU 装上了但 su 无反应 | 旧内核的 kprobes 不可靠，改 `KSU_HOOK_MODE=manual` |
| 模块挂载卸载不掉 | 5.9 以下内核需要 `ENABLE_PATH_UMOUNT=true` |
| 找不到 defconfig | `KERNEL_CONFIG` 写错，日志会列出可用的 defconfig |

## 感谢

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

**中文** | [English](README_EN.md#droidspaces-action)

`ENABLE_DROIDSPACES=true` 以启用 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 内核补丁，并为容器运行环境配置相关内核选项。

本 Action 参考 [Droidspaces 内核配置指南](https://github.com/ravindu644/Droidspaces-OSS/blob/v6.6.0/Documentation/zh-CN/Kernel-Configuration.md)，尝试应用相应补丁并启用容器运行所需的内核配置，包括网络隔离与防火墙相关选项。具体功能是否可用，仍取决于目标内核版本、配置依赖、补丁兼容性及设备运行环境。

如需裁剪功能或减少内核配置变更，请检查 `scripts/patches.sh`，并确认修改不会破坏你所需要的运行依赖。

确保你已阅读相关文档且**知道自己在做什么**。

> [!TIP]
> 
> 如果你已有内核构建环境，可以克隆此仓库，并设置配置项环境变量，在现有内核源码中应用对应的更改，例如：
>
> ```bash
> . scripts/config.sh; set +e; ENABLE_DROIDSPACES=true ENABLE_CUSTOM_PATCHES=true KERNEL_DIR=/path/to/src bash scripts/patches.sh
> ```
>
> 要应用此仓库的全部补丁，请使用以下命令：
>
> （注：固定内核配置是在 `build.sh` 阶段完成的）
>
> ```bash
> . config.env 2>/dev/null; . scripts/config.sh; set +e; export KERNEL_DIR=/path/to/src; bash scripts/kernelsu.sh; KSU_DIR=$KERNEL_DIR/KernelSU bash scripts/patches.sh
> ```

## 支持范围

| 内核版本 | 补丁目录 | 应用的补丁 |
| --- | --- | --- |
| `3.x`、`4.x` | `non-GKI/` | 目录内全部补丁 |
| `5.x`、`6.1`、`6.6` | `GKI/below-kernel-6.12/` | `SYSVIPC_KABI_PATCH`；若为 5.4/5.10 再追加 `002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch` |
| `6.12` | `GKI/kernel-6.12/` | 目录内全部补丁 |

> [!CAUTION]
>
> **启用 Droidspaces 功能时不支持 GrapheneOS 与 SuSFS** - 详情请参考 [Droidspaces Root 需求](https://github.com/ravindu644/Droidspaces-OSS/blob/v6.6.0/Documentation/zh-CN/README.md#root-%E9%9C%80%E6%B1%82)。

### 固定内核配置

Android 设备会通过 `/proc/config.gz` 检查内核配置与设备兼容性要求是否一致。启用 `ENABLE_STOCKCONFIG` 后，构建脚本会尝试使用仓库的原始内核配置作为 `IKCONFIG` 数据来源，以绕过 VINTF 对内核配置的检查。

此功能不等于禁用 VINTF 检查，也不能保证修复所有启动兼容性问题。

当启用该功能时，Actions 会额外上传实际构建配置 `out/.config` 作为 config artifact。`Release` 打包步骤还会尝试把其压缩为 `release/config.gz`。

> [!TIP]
> 
> 一般而言，启用此配置即可修复`您的设备内部出现了问题，请联系您的制造商了解详情`开机错误弹窗，部分第三方内核已内置了类似的功能。
> 
> 排查内核功能缺失时，应**优先检查实际构建配置**，而不要依据 `/proc/config.gz` 或 `KERNEL_CONFIG` 判断实际内核启用了哪些选项。

## 自定义补丁
`ENABLE_CUSTOM_PATCHES=true` 会依次尝试应用 `${REPO_ROOT}/patches/*.patch`，随后从 `${KERNEL_DIR}/scripts/setlocalversion` 中删除 `-dirty` 字符串，并在存在 `${REPO_ROOT}/patches/custom.sh` 时执行该脚本。

> [!WARNING]
> 
> 自定义补丁与 Droidspaces 内核补丁应用失败时都**不会终止构建**，你需要检查 Action 的日志以确认补丁是否应用成功。
>
> 自定义补丁在 Droidspaces 补丁之前应用。若补丁依赖特定代码状态或与前序补丁存在冲突，需自行调整顺序并验证最终源码。此文档可能过时，请以实际源码为准。

可供参考的补丁来源：
- [Droidspaces_Kernel_patch](https://github.com/Goldzxcbug/Droidspaces_Kernel_patch): CVE-UserNS, NTsync, cgroup_limits
- [android-gki-custom](https://github.com/1orz/android-gki-custom/tree/main/patches/android12-5.10): Ignore CRC checks, Overlayfs f2fs fix
- [WildKernels](https://github.com/WildKernels/kernel_patches): common
- [AOSP内核源码](https://android.googlesource.com/kernel/common): `git diff a..b path/to/file`

## Droidspaces 配置项
见 [`config.sh`](scripts/config.sh)，几个常用的：

| 选项 | 说明 |
| --- | --- |
| `ENABLE_DROIDSPACES` | 启用 Droidspaces 内核补丁与配置 |
| `SYSVIPC_KABI_PATCH` | 仅在内核版本 `5.x`、`6.1`、`6.6` 有效，用于指定 sysvipc kABI 补丁 |
| `ENABLE_STOCKCONFIG` | 启用 Android 固定内核配置，绕过 VINTF 兼容性检查，打包实际构建配置 |
| `ENABLE_CUSTOM_PATCHES` | 启用自定义补丁与脚本，去除 `-dirty` 字符串 |

## 额外仓库结构

若不存在 `patches/*.patch` 或 `patches/custom.sh`，则跳过对应的补丁或脚本处理。

```
patches/
  custom.sh            自定义脚本，可使用 patches.sh 中所有函数与变量
  *.patch              自定义补丁
```
