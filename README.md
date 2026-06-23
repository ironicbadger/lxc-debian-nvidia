# lxc-debian-nvidia

Debian 13 Proxmox LXC template with NVIDIA userland, Docker, and NVIDIA Container Toolkit.

+ [![Check Nvidia Driver version](https://github.com/ironicbadger/lxc-debian-nvidia/actions/workflows/check-nvidia-driver-version.yaml/badge.svg)](https://github.com/ironicbadger/lxc-debian-nvidia/actions/workflows/check-nvidia-driver-version.yaml)
+ [![Build LXC Template](https://github.com/ironicbadger/lxc-debian-nvidia/actions/workflows/build-template.yaml/badge.svg)](https://github.com/ironicbadger/lxc-debian-nvidia/actions/workflows/build-template.yaml)

## Quickstart

Create and configure a GPU-ready LXC from the latest release:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ironicbadger/lxc-debian-nvidia/main/proxmox/lxc-create.sh)" -- --id 123
```

The script downloads the latest Debian 13 template, applies the required Proxmox GPU config, and generates a root password if you do not pass one.

Fix an existing LXC in place:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ironicbadger/lxc-debian-nvidia/main/proxmox/lxc-modify.sh)" -- --id 123
```
