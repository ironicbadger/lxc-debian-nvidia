#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CORES=8
DEFAULT_MEMORY=8192
DEFAULT_DISK_SIZE=64
DEFAULT_SWAP=512
DEFAULT_BRIDGE="vmbr0"
DEFAULT_REPOSITORY="ironicbadger/lxc-debian-nvidia"
DEFAULT_TEMPLATE_FLAVOR="debian13"
DEFAULT_TEMPLATE_CACHE_DIR="/var/lib/vz/template/cache"

usage() {
    echo "Usage: $0 --id LXC_ID [--cores CORES] [--memory MEMORY] [--hostname HOSTNAME]"
    echo "          [--password PASSWORD] [--storage STORAGE] [--disk-size SIZE]"
    echo "          [--swap SWAP] [--bridge BRIDGE] [--driver-version VERSION]"
    echo "          [--template /path/to/template.tar.gz]"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command '$1' is not installed"
        exit 1
    }
}

generate_mac() {
    printf "BC:%02X:%02X:%02X:%02X:%02X\n" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

generate_password() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
}

detect_storage() {
    local storage
    while read -r storage; do
        case "$storage" in
            local-lvm|local-zfs|local) echo "$storage"; return 0 ;;
        esac
    done < <(pvesm status 2>/dev/null | awk 'NR>1 {print $1}')

    storage=$(pvesm status 2>/dev/null | awk 'NR>1 {print $1; exit}')
    if [[ -n "$storage" ]]; then
        echo "$storage"
        return 0
    fi

    echo "Error: unable to detect a Proxmox storage. Pass --storage explicitly."
    exit 1
}

latest_driver_version() {
    curl -fsSL "https://api.github.com/repos/${DEFAULT_REPOSITORY}/releases/latest" \
        | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"v\([^"]*\)",/\1/p' \
        | head -n1
}

add_if_not_exists() {
    local config="$1"
    if ! grep -Fxq "$config" "$CONFIG_FILE"; then
        echo "$config" >> "$CONFIG_FILE"
        echo "Added: $config"
    fi
}

apply_gpu_config() {
    if grep -q "^unprivileged:" "$CONFIG_FILE"; then
        sed -i 's/^unprivileged: 1/unprivileged: 0/' "$CONFIG_FILE"
    else
        add_if_not_exists "unprivileged: 0"
    fi

    add_if_not_exists "lxc.cgroup2.devices.allow: c 195:* rwm"
    add_if_not_exists "lxc.cgroup2.devices.allow: c 234:* rwm"
    add_if_not_exists "lxc.cgroup2.devices.allow: c 509:* rwm"
    add_if_not_exists "lxc.cgroup2.devices.allow: c 10:200 rwm"
    add_if_not_exists "lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file"
    add_if_not_exists "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
    add_if_not_exists "lxc.apparmor.profile: unconfined"
    add_if_not_exists "lxc.cgroup2.devices.allow: a"
    add_if_not_exists "lxc.cap.drop:"
}

download_template() {
    local version="$1"
    local template_path="${DEFAULT_TEMPLATE_CACHE_DIR}/nvidia-template-${DEFAULT_TEMPLATE_FLAVOR}-${version}.tar.gz"

    mkdir -p "$DEFAULT_TEMPLATE_CACHE_DIR"
    if [[ ! -f "$template_path" ]]; then
        echo "Downloading template ${version}..."
        curl -fL --progress-bar \
            "https://github.com/${DEFAULT_REPOSITORY}/releases/download/v${version}/nvidia-template-${DEFAULT_TEMPLATE_FLAVOR}-${version}.tar.gz" \
            -o "$template_path"
    fi

    echo "$template_path"
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --id) LXC_ID="$2"; shift ;;
        --cores) CORES="$2"; shift ;;
        --memory) MEMORY="$2"; shift ;;
        --hostname) HOSTNAME="$2"; shift ;;
        --password) ROOT_PASSWORD="$2"; shift ;;
        --storage) STORAGE="$2"; shift ;;
        --disk-size) DISK_SIZE="$2"; shift ;;
        --swap) SWAP="$2"; shift ;;
        --bridge) BRIDGE="$2"; shift ;;
        --driver-version) DRIVER_VERSION="$2"; shift ;;
        --template) TEMPLATE="$2"; shift ;;
        --help) usage ;;
        *) usage ;;
    esac
    shift
done

if [[ -z "${LXC_ID:-}" ]]; then
    usage
fi

require_command pct
require_command pvesm
require_command curl

BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}
CONFIG_FILE="/etc/pve/lxc/${LXC_ID}.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    CORES=${CORES:-$DEFAULT_CORES}
    MEMORY=${MEMORY:-$DEFAULT_MEMORY}
    DISK_SIZE=${DISK_SIZE:-$DEFAULT_DISK_SIZE}
    SWAP=${SWAP:-$DEFAULT_SWAP}
    HOSTNAME=${HOSTNAME:-gpu-${LXC_ID}}
    STORAGE=${STORAGE:-$(detect_storage)}
    ROOT_PASSWORD=${ROOT_PASSWORD:-$(generate_password)}
    DRIVER_VERSION=${DRIVER_VERSION:-$(latest_driver_version)}

    if [[ -z "$DRIVER_VERSION" ]]; then
        echo "Error: unable to determine the latest template version. Pass --driver-version or --template."
        exit 1
    fi

    if [[ -z "${TEMPLATE:-}" ]]; then
        TEMPLATE=$(download_template "$DRIVER_VERSION")
    fi

    if [[ ! -f "$TEMPLATE" ]]; then
        echo "Error: template ${TEMPLATE} not found"
        exit 1
    fi

    echo "Creating LXC ${LXC_ID} from ${TEMPLATE}..."
    pct create "$LXC_ID" "$TEMPLATE" \
        --cores "$CORES" \
        --memory "$MEMORY" \
        --hostname "$HOSTNAME" \
        --storage "$STORAGE" \
        --rootfs "$STORAGE:$DISK_SIZE" \
        --swap "$SWAP" \
        --password "$ROOT_PASSWORD" \
        --unprivileged 0 \
        --features keyctl=1,nesting=1 \
        --net0 "name=eth0,bridge=${BRIDGE},firewall=1,hwaddr=$(generate_mac),ip=dhcp,type=veth"

    echo "Root password: ${ROOT_PASSWORD}"
else
    echo "LXC ${LXC_ID} already exists. Updating settings and GPU config..."
    pct set "$LXC_ID" --features keyctl=1,nesting=1 >/dev/null

    SET_ARGS=()
    if [[ -n "${CORES:-}" ]]; then SET_ARGS+=(--cores "$CORES"); fi
    if [[ -n "${MEMORY:-}" ]]; then SET_ARGS+=(--memory "$MEMORY"); fi
    if [[ -n "${SWAP:-}" ]]; then SET_ARGS+=(--swap "$SWAP"); fi
    if [[ -n "${HOSTNAME:-}" ]]; then SET_ARGS+=(--hostname "$HOSTNAME"); fi
    if [[ -n "${ROOT_PASSWORD:-}" ]]; then SET_ARGS+=(--password "$ROOT_PASSWORD"); fi

    if [[ "${#SET_ARGS[@]}" -gt 0 ]]; then
        pct set "$LXC_ID" "${SET_ARGS[@]}" >/dev/null
    fi
fi

apply_gpu_config

echo "LXC ${LXC_ID} is ready."
echo "Start it with: pct start ${LXC_ID}"
echo "Verify GPU access with: pct exec ${LXC_ID} -- nvidia-smi"
