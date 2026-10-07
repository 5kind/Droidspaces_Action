#!/bin/bash
# ANDROID_SIMPLE_LMK conflicts with MEMCG and PSI;
# this script disables CONFIG_ANDROID_SIMPLE_LMK in favor of
# the standard Android memory management scheme using lmkd, MEMCG, and PSI.
info "Disable ANDROID_SIMPLE_LMK, SUSFS, and enable MEMCG, PSI, KSU, BINFMT_MISC"
scripts/config --file arch/arm64/configs/${DEVICE}_defconfig \
    -e CONFIG_PSI \
    -e CONFIG_MEMCG \
    -e CONFIG_MEMCG_SWAP \
    -d CONFIG_PSI_DEFAULT_DISABLED \
    -d CONFIG_ANDROID_SIMPLE_LMK \
    -d CONFIG_ANDROID_LOW_MEMORY_KILLER \
    \
    -e CONFIG_BINFMT_MISC \
    -e CONFIG_KSU \
    -e CONFIG_KSU_MANUAL_HOOK \
    -e CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK \
    -e CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK \
    -e CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK \
    -d CONFIG_KSU_SUSFS
# Also enable BINFMT_MISC, KSU_MANUAL_HOOK and disable KSU_SUSFS

# Remove buid-in kernelsu from the kernel tree; setup a symlink to the external kernelsu
info "Remove buid-in kernelsu from the kernel tree; setup a symlink to the external kernelsu"
sed -i '\|^[[:space:]]*source "drivers/kernelsu/kernel/Kconfig"$|d' drivers/Kconfig
sed -i '\|^[[:space:]]*obj-$(CONFIG_KSU)[[:space:]]*+= kernelsu/kernel/$|d' drivers/Makefile
rm -rf drivers/kernelsu && ln -sr ${KSU_DIR}/kernel drivers/kernelsu

# static_symbol_export <file.c> "<origin_symbol_full_spec_1>" "<origin_symbol_full_spec_2>" ...
# Use the full function declaration line whenever possible to avoid incorrect matches.
static_symbol_export() {
    local file=$1; shift
    local tmp; tmp=$(mktemp) || return 1
    local n=0 line spec found

    while IFS= read -r line || [[ -n $line ]]; do
        found=
        for spec in "$@"; do
            if [[ $line == *"$spec"* ]]; then
                printf '%s\n' "${line/static /}" >>"$tmp"
                n=$((n + 1))
                found=1
                break
            fi
        done
        [[ -n $found ]] || printf '%s\n' "$line" >>"$tmp"
    done < "$file"

    for spec in "$@"; do
        grep -qF -- "$spec" "$file" || warn "Not found: $spec"
    done

    cat -- "$tmp" >"$file"
    rm -f "$tmp"
    ok "Replaced $n static symbols in $file"
    return 0
}

info "Export symbols which are used by BakaSU"
# write_op export & sel_handle_status_ops export
static_symbol_export security/selinux/selinuxfs.c "ssize_t (*write_op[])(struct file *, char *, size_t) = {" "const struct file_operations sel_handle_status_ops = {"
# security_dump_masked_av & context_struct_compute_av
static_symbol_export security/selinux/ss/services.c "void security_dump_masked_av(struct policydb *policydb," "void context_struct_compute_av(struct policydb *policydb,"
info "Custom config & patches done"
