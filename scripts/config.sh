#!/usr/bin/env bash
# Resolve the build configuration, validate it, and export it to later steps.
#
# Resolution order (last wins):
#   1. built-in defaults below
#   2. the config file named by CONFIG_ENV (default: config.env)
#   3. workflow_dispatch inputs, passed in as IN_<KEY> environment variables
#
# The old workflow parsed config.env with
#     grep -w "$KEY" config.env | head -n1 | cut -d= -f2
# which truncates any value containing '=', matches commented-out lines, and
# matches a key that merely appears as a substring of a comment. That is why
# EXTRA_CMDS had to use a ':' separator. Both forms are still accepted here,
# but parsing is now anchored and comment-aware, so '=' in values is fine.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG_FILE=${CONFIG_ENV:-config.env}

# --------------------------------------------------------------- defaults ---

declare -A DEFAULTS=(
	[KERNEL_SOURCE]=""
	[KERNEL_SOURCE_BRANCH]=""
	[KERNEL_CONFIG]=""
	[KERNEL_IMAGE_NAME]="Image.gz-dtb"
	[ARCH]="arm64"
	[KERNEL_NAME]=""
	[ADD_LOCALVERSION_TO_FILENAME]="false"
	[EXTRA_CMDS]=""
	[CUSTOM_CMDS]=""

	# Toolchain
	[USE_CUSTOM_CLANG]="false"
	[CUSTOM_CLANG_SOURCE]=""
	[CUSTOM_CLANG_BRANCH]=""
	[CLANG_BRANCH]="main-kernel-2025"
	[CLANG_VERSION]="r547379"
	[USE_LLVM]="false"
	[ENABLE_GCC_ARM64]="false"
	[ENABLE_GCC_ARM32]="false"
	[USE_CUSTOM_GCC_64]="false"
	[CUSTOM_GCC_64_SOURCE]=""
	[CUSTOM_GCC_64_BRANCH]=""
	[CUSTOM_GCC_64_BIN]="aarch64-linux-android-"
	[USE_CUSTOM_GCC_32]="false"
	[CUSTOM_GCC_32_SOURCE]=""
	[CUSTOM_GCC_32_BRANCH]=""
	[CUSTOM_GCC_32_BIN]="arm-linux-androideabi-"

	# KernelSU
	[KSU_VARIANT]="none"
	[KSU_REF]=""
	[KSU_HOOK_MODE]="auto"
	[KSU_EXPECTED_SIZE]=""
	[KSU_EXPECTED_HASH]=""

	# Patches
	[ENABLE_SUSFS]="false"
	[SUSFS_REPO]="https://gitlab.com/simonpunk/susfs4ksu.git"
	[SUSFS_BRANCH]="auto"
	[ENABLE_PATH_UMOUNT]="false"
	[ENABLE_HIDE_STUFF]="false"
	[ENABLE_KPM]="false"
	[ENABLE_CUSTOM_PATCHES]="false"
	[ENABLE_DROIDSPACES]="false"
	[SYSVIPC_KABI_PATCH]="001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
	[DROIDSPACES_REPO]="https://github.com/ravindu644/Droidspaces-OSS.git"
	[DROIDSPACES_BRANCH]="v6.6.0"
	[DROIDSPACES_PATCHES_ROOT]="Documentation/resources/kernel-patches"
	[ENABLE_STOCKCONFIG]="false"
	[STOCKCONFIG_FLAGS]="-vts _stock"
	[STOCKCONFIG_MAKEFILE]="kernel/Makefile"

	# Kconfig tweaks
	[ADD_KPROBES_CONFIG]="false"
	[ADD_OVERLAYFS_CONFIG]="false"
	[DISABLE_LTO]="false"
	[DISABLE_CC_WERROR]="false"
	[EXTRA_DEFCONFIG]=""

	# Packaging
	[USE_CUSTOM_ANYKERNEL3]="false"
	[CUSTOM_ANYKERNEL3_SOURCE]=""
	[CUSTOM_ANYKERNEL3_BRANCH]=""
	[NEED_DTBO]="false"
	[BUILD_BOOT_IMG]="false"
	[SOURCE_BOOT_IMAGE]=""

	# Runner
	[ENABLE_CCACHE]="true"
	[REMOVE_UNUSED_PACKAGES]="true"
)

# Legacy spellings that must keep working for existing forks' config.env files.
declare -A ALIASES=(
	[DISABLE-LTO]="DISABLE_LTO"
	[KERNELSU_TAG]="KSU_REF"
	[APPLY_KSU_PATCH]="_LEGACY_APPLY_KSU_PATCH"
	[ENABLE_KERNELSU]="_LEGACY_ENABLE_KERNELSU"
)

# ----------------------------------------------------------------- parsing ---

# cfg_read FILE KEY -- first non-comment "KEY=value" or "KEY:value" line.
cfg_read() {
	local file=$1 key=$2
	[ -f "$file" ] || return 0
	sed -nE "s/\r$//; s/^[[:space:]]*${key}[[:space:]]*[=:][[:space:]]*(.*)$/\1/p" "$file" \
		| head -n1 \
		| sed -E 's/[[:space:]]+$//'
}

resolve() {
	local key val
	for key in "${!DEFAULTS[@]}"; do
		val=${DEFAULTS[$key]}

		local from_file
		from_file=$(cfg_read "$CONFIG_FILE" "$key")
		[ -n "$from_file" ] && val=$from_file

		# Workflow inputs win over the file, but only when actually provided.
		#
		# The sentinel "config" means "leave the config file's value alone".
		# The dispatch form needs it because a GitHub boolean input always has
		# a concrete value: with a plain checkbox defaulting to false, a user
		# who set ENABLE_SUSFS=true in their profile and then ran the form
		# without touching anything would silently get SUSFS turned back off.
		local in_var="IN_${key}"
		local in_val=${!in_var:-}
		if [ -n "$in_val" ] && [ "$in_val" != "config" ]; then
			val=$in_val
		fi

		CFG[$key]=$val
	done

	# Fold legacy keys in only where the modern key was not already set.
	local legacy modern
	for legacy in "${!ALIASES[@]}"; do
		modern=${ALIASES[$legacy]}
		local lv
		lv=$(cfg_read "$CONFIG_FILE" "$legacy")
		[ -n "$lv" ] || continue
		case "$modern" in
			_LEGACY_*) CFG[$modern]=$lv ;;
			*)
				# Only honour the legacy spelling when the modern one is absent
				# from the file and no input overrode it.
				local mv in_var="IN_${modern}"
				mv=$(cfg_read "$CONFIG_FILE" "$modern")
				if [ -z "$mv" ] && [ -z "${!in_var:-}" ]; then
					CFG[$modern]=$lv
					debug "legacy key ${legacy} -> ${modern}=${lv}"
				fi
				;;
		esac
	done
}

# --------------------------------------------- legacy compatibility bridge ---

# Old config.env used ENABLE_KERNELSU=true plus KERNELSU_TAG to mean
# "install tiann/KernelSU". Translate that into the new variant selector so
# existing forks keep building without editing anything.
apply_legacy_bridge() {
	local legacy_enable=${CFG[_LEGACY_ENABLE_KERNELSU]:-}
	local legacy_patch=${CFG[_LEGACY_APPLY_KSU_PATCH]:-}

	if [ "${CFG[KSU_VARIANT]}" = "none" ] && is_true "$legacy_enable"; then
		CFG[KSU_VARIANT]="kernelsu"
		warn "config.env uses the legacy ENABLE_KERNELSU flag; treating it as KSU_VARIANT=kernelsu."
		warn "Set KSU_VARIANT explicitly to pick a fork (kernelsu-next, sukisu-ultra, resukisu, ...)."
	fi

	# APPLY_KSU_PATCH used to mean "run the bundled sed script to add manual
	# hooks". That is now the 'manual' hook mode.
	if is_true "$legacy_patch" && [ "${CFG[KSU_HOOK_MODE]}" = "auto" ]; then
		CFG[KSU_HOOK_MODE]="manual"
		warn "config.env uses the legacy APPLY_KSU_PATCH flag; treating it as KSU_HOOK_MODE=manual."
	fi

	unset 'CFG[_LEGACY_ENABLE_KERNELSU]' 'CFG[_LEGACY_APPLY_KSU_PATCH]'
}

# -------------------------------------------------------------- validation ---

validate() {
	local errors=0
	_err() { warn "config: $*"; errors=$((errors + 1)); }

	[ -n "${CFG[KERNEL_SOURCE]}" ]        || _err "KERNEL_SOURCE is required"
	[ -n "${CFG[KERNEL_SOURCE_BRANCH]}" ] || _err "KERNEL_SOURCE_BRANCH is required"
	[ -n "${CFG[KERNEL_CONFIG]}" ]        || _err "KERNEL_CONFIG is required"
	[ -n "${CFG[KERNEL_IMAGE_NAME]}" ]    || _err "KERNEL_IMAGE_NAME is required"

	case "${CFG[ARCH]}" in
		arm64 | arm | x86_64 | riscv) ;;
		*) _err "ARCH must be one of arm64/arm/x86_64/riscv (got '${CFG[ARCH]}')" ;;
	esac

	case "${CFG[KSU_VARIANT]}" in
		none | kernelsu | kernelsu-next | sukisu-ultra | resukisu | rsuntk | backslashxx) ;;
		*) _err "unknown KSU_VARIANT '${CFG[KSU_VARIANT]}'" ;;
	esac

	case "${CFG[KSU_HOOK_MODE]}" in
		auto | kprobes | manual | tracepoint | syscall | none) ;;
		*) _err "unknown KSU_HOOK_MODE '${CFG[KSU_HOOK_MODE]}'" ;;
	esac

	if [ "${CFG[KSU_VARIANT]}" = "none" ]; then
		is_true "${CFG[ENABLE_SUSFS]}" &&
			_err "ENABLE_SUSFS requires a KSU_VARIANT other than 'none'"
		is_true "${CFG[ENABLE_KPM]}" &&
			_err "ENABLE_KPM requires KSU_VARIANT=sukisu-ultra"
	fi

	# KPM is a SukiSU-Ultra feature and its patch_linux tool is 64-bit only.
	if is_true "${CFG[ENABLE_KPM]}"; then
		[ "${CFG[KSU_VARIANT]}" = "sukisu-ultra" ] ||
			_err "ENABLE_KPM is only supported with KSU_VARIANT=sukisu-ultra (got '${CFG[KSU_VARIANT]}')"
		[ "${CFG[ARCH]}" = "arm64" ] ||
			_err "ENABLE_KPM requires ARCH=arm64"
	fi

	if is_true "${CFG[BUILD_BOOT_IMG]}" && [ -z "${CFG[SOURCE_BOOT_IMAGE]}" ]; then
		_err "BUILD_BOOT_IMG=true requires SOURCE_BOOT_IMAGE"
	fi

	if is_true "${CFG[USE_CUSTOM_CLANG]}" && [ -z "${CFG[CUSTOM_CLANG_SOURCE]}" ]; then
		_err "USE_CUSTOM_CLANG=true requires CUSTOM_CLANG_SOURCE"
	fi

	if is_true "${CFG[USE_CUSTOM_ANYKERNEL3]}" && [ -z "${CFG[CUSTOM_ANYKERNEL3_SOURCE]}" ]; then
		_err "USE_CUSTOM_ANYKERNEL3=true requires CUSTOM_ANYKERNEL3_SOURCE"
	fi

	[ "$errors" -eq 0 ] || die "${errors} configuration error(s); fix ${CONFIG_FILE} or the workflow inputs"
}

# ------------------------------------------------------------------- main ---

declare -A CFG
resolve
apply_legacy_bridge
validate

# Derive the device label from the defconfig name, as before.
DEVICE=$(printf '%s' "${CFG[KERNEL_CONFIG]}" | sed 's!.*/!!; s/_defconfig$//; s/_user$//; s/-perf$//')
[ -n "${CFG[KERNEL_NAME]}" ] && DEVICE=${CFG[KERNEL_NAME]}
CFG[DEVICE]=$DEVICE

summary "### Build configuration"
summary ""
summary "| Item | Value |"
summary "| --- | --- |"

group "Resolved configuration"
for key in $(printf '%s\n' "${!CFG[@]}" | sort); do
	printf '  %-32s = %s\n' "$key" "${CFG[$key]}"
	export_env "$key" "${CFG[$key]}"
done
endgroup

export_env BUILD_TIME "$(TZ=${BUILD_TZ:-Asia/Shanghai} date '+%Y%m%d%H%M')"

ok "configuration resolved (device: ${DEVICE})"
