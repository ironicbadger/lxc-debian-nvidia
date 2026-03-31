#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 --id LXC_ID"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --id) LXC_ID="$2"; shift ;;
        --help) usage ;;
        *) usage ;;
    esac
    shift
done

if [[ -z "${LXC_ID:-}" ]]; then
    usage
fi

CONFIG_FILE="/etc/pve/lxc/${LXC_ID}.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file for LXC ID ${LXC_ID} not found at ${CONFIG_FILE}"
    exit 1
fi

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

pct set "$LXC_ID" --features keyctl=1,nesting=1 >/dev/null
apply_gpu_config

echo "Updated LXC ${LXC_ID}. Restart the container if it is already running."
