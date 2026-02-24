# CM4 NVMe Boot + Mender A/B (U-Boot Mender)

This guide describes the complete workflow used in this repository to boot a
CM4 from NVMe with `uboot-mender` and prepare a Mender A/B image.

## 1. Prerequisites

- Host: Linux/WSL with required `mender-convert` dependencies.
- Toolchain: `aarch64-linux-gnu-gcc` in `PATH`.
- Input image: Raspberry Pi OS 64-bit raw `.img`.
- Hardware: CM4 + carrier with PCIe/NVMe support.

Optional but recommended:

- Stable serial console for U-Boot and kernel logs.
- EEPROM configured to prefer NVMe boot (`BOOT_ORDER` according to your setup).

## 2. Build NVMe-enabled U-Boot bundle

From repository root:

```bash
scripts/uboot/build-uboot-rpi64-nvme.sh
```

Expected output:

- `assets/raspberrypi_arm64_cm4_nvme-2024.04.tar.gz`

The bundle contains:

- `u-boot.bin`
- `fw_printenv`
- `fw_env.config`
- `uboot-git-log.txt`

## 3. Convert OS image for Mender on NVMe

```bash
export MENDER_ARTIFACT_NAME="cm4-nvme-trixie-ab6gb"
sudo --preserve-env=MENDER_ARTIFACT_NAME ./mender-convert \
  --disk-image input/<raspios-image>.img \
  --config configs/local/cm4_nvme_trixie_64_ab6gb_config
```

Expected outputs in `deploy/`:

- `*.img`
- `*.ext4`
- `*.mender`
- `*.cfg`

## 4. First boot procedure

After flashing the converted image and booting into U-Boot:

1. Reset old environment once (important after switching from MMC setup):

```text
env default -a
saveenv
reset
```

2. Verify NVMe availability:

```text
pci enum
nvme scan
nvme info
```

3. Verify Mender paths:

```text
run mender_setup
printenv mender_uboot_root mender_kernel_root
```

Expected values:

- `mender_uboot_root=nvme 0:2`
- `mender_kernel_root=/dev/nvme0n1p2`

## 5. Runtime validation checklist

In U-Boot:

- `nvme scan` must complete without `err=-110`.
- `load ${mender_uboot_root} ${kernel_addr_r} /boot/vmlinux` must succeed.

In Linux:

- Rootfs from NVMe (`findmnt /` should show `/dev/nvme0n1p2` or matching A/B slot).
- `cat /proc/cmdline` includes `root=${mender_kernel_root}` resolved to NVMe.

## 6. Troubleshooting

### CRLF / shell parse errors

If you see `$'\r': command not found`, convert scripts/configs to LF and set
Git EOL policy:

```bash
git config --global core.autocrlf input
git config --global core.eol lf
```

This repo includes `.gitattributes` to enforce LF for key file types.

### `nvme scan` timeout `err=-110`

Use the patch and build flow from `scripts/uboot/`. This repo contains fixes
for CM4/RPi4 DMA/PCIe/NVMe translation issues seen in stock `mender-rpi-2024.04`.

### No kernel logs after `Starting kernel ...`

Do not interrupt normal autoboot flow while debugging unless needed.
When testing manually, load matching kernel+initrd+DTB and set explicit serial
console bootargs.

