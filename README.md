# TrueNAS NVIDIA Driver Updater

Build and deploy **any** NVIDIA proprietary driver as a `systemd-sysext` image (`nvidia.raw`) for **TrueNAS SCALE** — fully automated via Docker.

TrueNAS SCALE ships with a specific NVIDIA driver version baked into its immutable root filesystem. This tool lets you compile and package a different driver version (newer or older) without modifying the base OS, using the `systemd-sysext` overlay mechanism that TrueNAS natively supports.

---

## Features

- **Fully automated** — downloads TrueNAS update file, extracts kernel headers, compiles the driver, packages everything
- **Production-kernel aware** — correctly selects the production kernel over debug variants
- **Complete module database** — ships a combined `modules.dep` covering all system + NVIDIA modules (no `depmod -a` needed on read-only target)
- **nvidia-container-toolkit included** — Docker GPU passthrough works out of the box
- **Before/after filesystem diff** — captures 100% of NVIDIA installer output, no fragile glob patterns
- **Backup & rollback** — deployment script preserves previous images with timestamps

## Quick Start

### 1. Configure

Edit `docker-compose.yaml` with your target versions:

```yaml
environment:
  - NVIDIA_VERSION=595.58.03       # NVIDIA driver version
  - TRUENAS_VERSION=25.10.0        # TrueNAS SCALE version
  - TRUENAS_CODENAME=Goldeye       # TrueNAS release codename
```

### 2. Build

```bash
docker compose up --build
```

The build takes ~10-15 minutes (mostly kernel module compilation). The output `nvidia.raw` will be in `./output/`.

### 3. Deploy to TrueNAS

Copy `output/nvidia.raw` and `deploy-nvidia.sh` to your TrueNAS system, then:

```bash
chmod +x deploy-nvidia.sh
./deploy-nvidia.sh nvidia.raw
```

The deploy script handles everything:
- Unmerges active sysext extensions
- Unlocks the read-only `/usr` ZFS dataset
- Backs up the existing `nvidia.raw` (timestamped)
- Installs the new image
- Re-locks the dataset and merges extensions

### 4. Verify

```bash
nvidia-smi
```

---

## TrueNAS Version Reference

| TrueNAS SCALE Version | Codename     |
|------------------------|--------------|
| 25.10.x                | Goldeye      |
| 25.04.x                | Fangtooth    |
| 24.10.x                | Electric Eel |
| 24.04.x                | Dragonfish   |
| 23.10.x                | Cobia        |

> Use the codename matching your TrueNAS version for `TRUENAS_CODENAME`.

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                   Docker Build Container                │
│                                                         │
│  1. Download TrueNAS update file (squashfs)             │
│  2. Extract nested rootfs → kernel headers + modules    │
│  3. Detect production kernel version                    │
│  4. Install nvidia-container-toolkit via apt            │
│  5. Take filesystem BEFORE snapshot                     │
│  6. Compile NVIDIA driver against TrueNAS headers       │
│  7. Take filesystem AFTER snapshot                      │
│  8. Diff → captures ALL new files                       │
│  9. Stage into sysext tree (/usr only)                  │
│ 10. Build combined modules.dep (system + nvidia)        │
│ 11. Package as nvidia.raw (squashfs, gzip)              │
└─────────────────────────────────────────────────────────┘
```

### Why systemd-sysext?

TrueNAS SCALE uses an immutable root filesystem. `systemd-sysext` provides a supported overlay mechanism that merges the contents of `/usr` from extension images on top of the base OS — without modifying it. This means:

- **Survives reboots** — extensions are re-merged on boot
- **Survives updates** — rebuild `nvidia.raw` with new kernel headers after a TrueNAS update
- **Clean rollback** — `systemd-sysext unmerge` restores the original state

### Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| `--kernel-module-type=open` | Open-source kernel modules avoid `MITIGATION_RETHUNK` / naked-return hard errors on TrueNAS's hardened kernel |
| `--no-drm` | TrueNAS kernel lacks `drm_fbdev_ttm_driver_fbdev_probe`, causing `nvidia-drm.ko` to fail with "Unknown symbol". DRM/KMS is for display output — irrelevant on a headless NAS |
| Production kernel preference | TrueNAS ships both debug and production kernels; the production kernel is what actually boots. Alphabetical sorting would pick the wrong one |
| Combined `modules.dep` | The sysext's `modules.dep` overlays the system's via overlayfs. Shipping an nvidia-only `modules.dep` would make all other kernel modules (nf_tables, bridge, etc.) invisible, breaking Docker and networking |
| gzip compression | Matches TrueNAS's own squashfs convention for consistent image sizes |

---

## Advanced Usage

### Using a Pre-downloaded Update File

To avoid re-downloading the ~1.8 GB TrueNAS update file on every build:

```bash
# Download once
wget -O truenas.update "https://download.truenas.com/TrueNAS-SCALE-Goldeye/25.10.0/TrueNAS-SCALE-25.10.0.update?download=1"

# Build — the script detects the local file and skips download
docker compose up --build
```

### Rollback to Previous Driver

The deploy script saves backups in a `backups/` directory alongside itself (keeps the 5 most recent):

```bash
# List available backups
ls -la backups/

# Rollback
./deploy-nvidia.sh backups/nvidia.raw.backup_20260422_160428
```

### After a TrueNAS Update

When TrueNAS updates its kernel, you need to rebuild:

1. Update `TRUENAS_VERSION` in `docker-compose.yaml`
2. Remove any cached `truenas.update` file
3. Run `docker compose up --build`
4. Deploy the new `nvidia.raw`

---

## File Structure

```
.
├── Dockerfile              # Debian 12 build container
├── docker-compose.yaml     # Build configuration (versions here)
├── entrypoint.sh           # Main build script
├── deploy-nvidia.sh        # TrueNAS deployment script
├── output/                 # Build output (nvidia.raw)
├── backups/                # Previous nvidia.raw backups (auto-managed)
├── LICENSE
└── README.md
```

## Requirements

- **Build machine**: Docker with `docker compose`
- **TrueNAS**: SCALE 24.04+ (systemd-sysext support)
- **GPU**: Any NVIDIA GPU supported by the target driver version

## Troubleshooting

### `nvidia-smi` fails with "couldn't communicate with the NVIDIA driver"

The kernel modules were compiled for the wrong kernel version. Verify with:
```bash
uname -r                    # running kernel
modinfo nvidia | grep vermagic  # module's target kernel
```
These must match. Rebuild with the correct `TRUENAS_VERSION`.

### Docker fails with "iptables: Failed to initialize nft"

The sysext's `modules.dep` is overriding the system's module database. This was a bug in early versions — ensure you're using the latest build script which ships a combined `modules.dep`.

### Docker warns "nvidia-container-runtime: no such file or directory"

The `nvidia-container-toolkit` package is missing from the sysext. Ensure you're using the latest build script which installs it via apt.

---

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- Inspired by the official [TrueNAS SCALE extension build system](https://github.com/truenas/scale-build)
- NVIDIA driver installer from [NVIDIA's official download site](https://www.nvidia.com/Download/index.aspx)
- nvidia-container-toolkit from [NVIDIA's container toolkit repo](https://github.com/NVIDIA/nvidia-container-toolkit)
