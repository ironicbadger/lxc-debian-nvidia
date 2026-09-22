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

The latest release must contain a `nvidia-template-debian13-<driver-version>.tar.gz` asset. After this change is merged, run the **Build LXC Template** workflow from `main` to publish that asset; merging alone does not trigger a release build. The NVIDIA driver version must match the Proxmox host's driver. Use `--driver-version VERSION` to select a matching release, or `--template /path/to/template.tar.gz` to use a local template without contacting GitHub. Storage is selected from active stores supporting container root filesystems; use `--storage STORAGE` to override it.

Fix an existing LXC in place:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ironicbadger/lxc-debian-nvidia/main/proxmox/lxc-modify.sh)" -- --id 123
```
