#!/usr/bin/env bash
#
# droidspaces-check-config.sh
# Check kernel configuration for Droidspaces support.
#
# Kernel major version selects the configuration set:
#   < 5: non-GKI, full feature set
#   >=5: GKI, reduced set to avoid vendor kABI breakage
#
# The kernel version is read from the config file header when present
# (e.g. "# Linux/arm64 4.14.356 Kernel Configuration"), so that checking
# a cross-compiled or offline config does not depend on the host kernel.
# Falls back to uname -r when the header is absent.
#
# Flag tables are structured so that GKI is a strict subset of non-GKI:
#
#   COMMON_REQ       required for both
#   COMMON_OPT       recommended for both
#   NON_GKI_EXTRA_REQ  required only on non-GKI
#   NON_GKI_EXTRA_OPT  recommended only on non-GKI
#
#   non-GKI: COMMON_* + NON_GKI_EXTRA_*
#   GKI:     COMMON_*
#
# MUST_N tables are kept separate because an option can be recommended on
# one side and forbidden on the other:
#   CONFIG_CFS_BANDWIDTH / CONFIG_CGROUP_PIDS
#     recommended on non-GKI, forbidden on GKI (kABI breakage)
#
# Exit status:
#   0: all required flags are enabled
#   1: one or more required flags are missing or incorrect
#   2: usage or configuration file error

set -euo pipefail

EXITCODE=0

usage() {
    cat >&2 <<EOF
Usage: $0 [config-file]

Check kernel configuration for Droidspaces support.

  config-file  Path to a .config or /proc/config.gz
               Defaults to /proc/config.gz, then /boot/config-\$(uname -r).

Exit status:
  0  All required flags are enabled
  1  Required flags are missing or incorrect
  2  Usage or configuration file error
EOF
}

# Color output follows Docker's check-config.sh.
USE_COLOR=true
if [[ ${NO_COLOR:-0} == 1 || ! -t 1 ]]; then
    USE_COLOR=false
fi

color() {
    [[ $USE_COLOR == true ]] || return 0

    local code=
    case ${1:-reset} in
        bold)   code='1' ;;
        red)    code='31' ;;
        green)  code='32' ;;
        yellow) code='33' ;;
        white)  code='37' ;;
        reset)  code='0' ;;
    esac

    printf '\033[%sm' "$code"
}

wrap_color() {
    local message=$1
    local style=${2:-white}

    color "$style"
    printf '%s' "$message"
    color reset
}

wrap_good() {
    wrap_color "$1" white
    printf ': '
    wrap_color "$2" green
    printf '\n'
}

wrap_bad() {
    wrap_color "$1" white
    printf ': '
    wrap_color "$2" red
    printf '\n'
}

wrap_warning() {
    wrap_color "$*" yellow >&2
    printf '\n' >&2
}

# ---------------------------------------------------------------------------
# Configuration tables.
#
# REQ/OPT entries use NAME=VALUE; MUST_N entries use NAME.
# ---------------------------------------------------------------------------

# --- shared between GKI and non-GKI ----------------------------------------

COMMON_REQ=(
    # IPC
    CONFIG_SYSVIPC=y
    CONFIG_POSIX_MQUEUE=y

    # Namespaces
    CONFIG_IPC_NS=y
    CONFIG_PID_NS=y

    # Device management
    CONFIG_DEVTMPFS=y

    # Networking
    CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
)

COMMON_OPT=(
    # Docker unsafe procfs compatibility
    CONFIG_USER_NS=y

    # NAT66
    CONFIG_IP6_NF_NAT=y
    CONFIG_IP6_NF_TARGET_MASQUERADE=y

    # UFW
    CONFIG_NETFILTER_XT_TARGET_REJECT=y
    CONFIG_NETFILTER_XT_TARGET_LOG=y
    CONFIG_NETFILTER_XT_MATCH_RECENT=y

    # Fail2ban
    CONFIG_IP_SET=y
    CONFIG_IP_SET_HASH_IP=y
    CONFIG_IP_SET_HASH_NET=y
    CONFIG_NETFILTER_XT_SET=y

    # tmpfs xattr / posix acl (NixOS)
    CONFIG_TMPFS_POSIX_ACL=y
    CONFIG_TMPFS_XATTR=y
)

# --- non-GKI only (kernel major < 5) ---------------------------------------

NON_GKI_EXTRA_REQ=(
    # IPC
    CONFIG_SYSCTL=y

    # Namespaces
    CONFIG_NAMESPACES=y
    CONFIG_UTS_NS=y
    CONFIG_NET_NS=y

    # Seccomp
    CONFIG_SECCOMP=y
    CONFIG_SECCOMP_FILTER=y

    # Cgroups (core)
    CONFIG_CGROUPS=y
    CONFIG_CGROUP_DEVICE=y
    CONFIG_CGROUP_SCHED=y
    CONFIG_FAIR_GROUP_SCHED=y
    CONFIG_CGROUP_FREEZER=y
    CONFIG_CGROUP_NET_PRIO=y

    # Filesystems
    CONFIG_OVERLAY_FS=y

    # Firmware loading
    CONFIG_FW_LOADER=y
    CONFIG_FW_LOADER_USER_HELPER=y
    CONFIG_FW_LOADER_COMPRESS=y

    # Networking (core)
    CONFIG_VETH=y
    CONFIG_BRIDGE=y
    CONFIG_NETFILTER=y
    CONFIG_BRIDGE_NETFILTER=y
    CONFIG_NETFILTER_ADVANCED=y
    CONFIG_NF_CONNTRACK=y
    CONFIG_IP_NF_IPTABLES=y
    CONFIG_IP_NF_FILTER=y
    CONFIG_NF_NAT=y
    CONFIG_NF_TABLES=y
    CONFIG_IP_NF_TARGET_MASQUERADE=y
    CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y
    CONFIG_NETFILTER_XT_TARGET_TCPMSS=y
    CONFIG_NF_CONNTRACK_NETLINK=y
    CONFIG_NF_NAT_REDIRECT=y
    CONFIG_IP_ADVANCED_ROUTER=y
    CONFIG_IP_MULTIPLE_TABLES=y
)

NON_GKI_EXTRA_OPT=(
    # Resource limits (--memory, --cpus, --pids-limit)
    CONFIG_MEMCG=y
    CONFIG_CFS_BANDWIDTH=y
    CONFIG_CGROUP_PIDS=y
    CONFIG_CGROUP_CPUACCT=y

    # Legacy IPv4 compatibility
    CONFIG_NF_CONNTRACK_IPV4=y
    CONFIG_NF_NAT_IPV4=y
    CONFIG_IP_NF_NAT=y

    # NAT66 (remaining pieces)
    CONFIG_IPV6=y
    CONFIG_IPV6_MULTIPLE_TABLES=y
    CONFIG_IP6_NF_IPTABLES=y
    CONFIG_IP6_NF_FILTER=y
    CONFIG_IP6_NF_MANGLE=y

    # Legacy IPv6 compatibility
    CONFIG_NF_CONNTRACK_IPV6=y
    CONFIG_NF_NAT_IPV6=y

    # UFW (remaining pieces)
    CONFIG_NETFILTER_XT_MATCH_COMMENT=y
    CONFIG_NETFILTER_XT_MATCH_STATE=y
    CONFIG_NETFILTER_XT_MATCH_CONNTRACK=y
    CONFIG_NETFILTER_XT_MATCH_MULTIPORT=y
    CONFIG_NETFILTER_XT_MATCH_HL=y
    CONFIG_IP_NF_TARGET_REJECT=y
    CONFIG_IP_NF_TARGET_ULOG=y

    # Fail2ban (remaining pieces)
    CONFIG_NETFILTER_XT_MATCH_LIMIT=y
    CONFIG_NETFILTER_XT_MATCH_HASHLIMIT=y
    CONFIG_NETFILTER_XT_MATCH_OWNER=y
    CONFIG_NETFILTER_XT_MATCH_PKTTYPE=y
    CONFIG_NETFILTER_XT_MATCH_MARK=y
    CONFIG_NETFILTER_XT_TARGET_MARK=y
    CONFIG_NETFILTER_NETLINK_QUEUE=y
    CONFIG_NETFILTER_NETLINK_LOG=y
    CONFIG_NETFILTER_XT_TARGET_NFLOG=y
)

NON_GKI_MUST_N=(
    # Disable on older kernels so container networking works
    CONFIG_ANDROID_PARANOID_NETWORK
)

# --- GKI-specific MUST_N (kernel major >= 5) -------------------------------

GKI_MUST_N=(
    # These options can alter exported symbol CRCs through changes to
    # scheduler or cgroup structures. Recommended on non-GKI, but keep
    # them disabled on GKI when using prebuilt vendor modules unless
    # the ABI impact has been verified.
    CONFIG_CFS_BANDWIDTH
    CONFIG_CGROUP_PIDS
)

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

declare -A CFG=()

parse_config() {
    local file=$1
    local line key value

    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^[[:space:]]*# ]]; then
            if [[ $line =~ ^#[[:space:]]*(CONFIG_[[:alnum:]_]+)[[:space:]]+is[[:space:]]+not[[:space:]]+set$ ]]; then
                CFG["${BASH_REMATCH[1]}"]=n
            fi
            continue
        fi

        if [[ $line =~ ^(CONFIG_[[:alnum:]_]+)=(.*)$ ]]; then
            key=${BASH_REMATCH[1]}
            value=${BASH_REMATCH[2]}
            CFG["$key"]=$value
        fi
    done < <(
        case $file in
            *.gz) gzip -cd -- "$file" ;;
            *)    cat -- "$file" ;;
        esac
    )
}

# Read the kernel version from the config header:
#   # Linux/arm64 4.14.356 Kernel Configuration
# Only the leading comment block is scanned. Returns 1 when the header
# is absent, so the caller can fall back to uname -r.
detect_config_version() {
    local file=$1
    local line

    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line =~ ^#[[:space:]]*Linux/[^[:space:]]+[[:space:]]+([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi

        # Stop at the first non-comment line.
        [[ $line =~ ^[[:space:]]*# ]] || break
    done < <(
        case $file in
            *.gz) gzip -cd -- "$file" ;;
            *)    cat -- "$file" ;;
        esac
    )

    return 1
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

check_flag() {
    local name=$1
    local want=$2
    local got=${CFG[$1]-}

    if [[ -z ${CFG[$name]+x} ]]; then
        wrap_bad "$name" "missing (required: $want)"
        EXITCODE=1
    elif [[ $got != "$want" ]]; then
        wrap_bad "$name" "set to $got (required: $want)"
        EXITCODE=1
    else
        wrap_good "$name" "enabled ($want)"
    fi
}

check_flags() {
    local entry name value

    for entry in "$@"; do
        name=${entry%%=*}
        value=${entry#*=}
        printf -- '- '
        check_flag "$name" "$value"
    done
}

# Missing or incorrectly set optional flags are warnings only.
check_optional_flag() {
    local name=$1
    local want=$2
    local got=${CFG[$1]-}

    if [[ -z ${CFG[$name]+x} ]]; then
        wrap_warning "$name: missing (recommended: $want)"
    elif [[ $got != "$want" ]]; then
        wrap_warning "$name: set to $got (recommended: $want)"
    else
        wrap_good "$name" "enabled ($want)"
    fi
}

check_optional_flags() {
    local entry name value

    for entry in "$@"; do
        name=${entry%%=*}
        value=${entry#*=}
        printf -- '- '
        check_optional_flag "$name" "$value"
    done
}

# These flags must not be enabled.
check_forbidden_flags() {
    local name

    for name in "$@"; do
        printf -- '- '
        if [[ ${CFG[$name]-} == y ]]; then
            wrap_warning "$name: enabled (should not be y)"
        else
            wrap_good "$name" 'disabled'
        fi
    done
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
    if (( $# > 1 )); then
        usage
        exit 2
    fi

    local kernel_version kernel_major config mode
    local -a req_list opt_list forbidden_list

    # Locate the config file first.
    if (( $# == 1 )); then
        config=$1
    elif [[ -r /proc/config.gz ]]; then
        config=/proc/config.gz
    elif [[ -r /boot/config-$(uname -r) ]]; then
        config=/boot/config-$(uname -r)
    else
        wrap_warning 'error: cannot find kernel configuration'
        wrap_warning "  usage: $0 /path/to/.config"
        exit 2
    fi

    if [[ ! -r $config || ! -f $config ]]; then
        wrap_warning "error: cannot read kernel configuration: $config"
        exit 2
    fi

    if [[ $config == *.gz ]] && ! gzip -t -- "$config" 2>/dev/null; then
        wrap_warning "error: invalid gzip configuration: $config"
        exit 2
    fi

    # Derive the kernel version from the config header when possible so
    # that cross-compiled or offline configs do not depend on uname -r.
    if kernel_version=$(detect_config_version "$config"); then
        :
    else
        kernel_version=$(uname -r)
        wrap_warning "warning: config has no version header, falling back to uname: $kernel_version"
    fi

    kernel_major=${kernel_version%%.*}

    if [[ ! $kernel_major =~ ^[0-9]+$ ]]; then
        wrap_warning "error: cannot determine kernel major version: $kernel_version"
        exit 2
    fi

    printf 'Kernel: %s\n' "$kernel_version"
    printf 'Config: %s\n' "$config"
    printf 'Mode:   '

    # Build the effective lists. GKI is intentionally COMMON_* only, so
    # that the subset invariant holds by construction.
    if (( kernel_major < 5 )); then
        mode=non-GKI
        req_list=( "${COMMON_REQ[@]}" "${NON_GKI_EXTRA_REQ[@]}" )
        opt_list=( "${COMMON_OPT[@]}" "${NON_GKI_EXTRA_OPT[@]}" )
        forbidden_list=( "${NON_GKI_MUST_N[@]}" )
    else
        mode=GKI
        req_list=( "${COMMON_REQ[@]}" )
        opt_list=( "${COMMON_OPT[@]}" )
        forbidden_list=( "${GKI_MUST_N[@]}" )
    fi

    printf '%s\n\n' "$mode"

    if ! parse_config "$config"; then
        wrap_warning "error: failed to read kernel configuration: $config"
        exit 2
    fi

    echo 'Required flags:'
    check_flags "${req_list[@]}"

    echo
    echo 'Recommended flags:'
    check_optional_flags "${opt_list[@]}"

    echo
    echo 'Flags that must not be enabled:'
    check_forbidden_flags "${forbidden_list[@]}"

    echo
    if (( EXITCODE == 0 )); then
        wrap_good 'Result' 'all required flags are enabled'
    else
        wrap_bad 'Result' 'one or more required flags are missing or incorrect'
    fi

    exit "$EXITCODE"
}

main "$@"

