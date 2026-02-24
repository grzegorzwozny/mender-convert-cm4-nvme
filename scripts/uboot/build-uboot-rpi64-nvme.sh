#!/usr/bin/env bash
# Copyright 2026 Northern.tech AS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/uboot/build-uboot-rpi64-nvme.sh [options]

Options:
  --branch <name>       uboot-mender branch/tag (default: mender-rpi-2024.04)
  --defconfig <name>    U-Boot defconfig (default: rpi_arm64_defconfig)
  --board-name <name>   Output tar prefix (default: raspberrypi_arm64_cm4_nvme)
  --output-dir <path>   Destination dir for tarball (default: assets)
  --work-dir <path>     Build workspace (default: work/uboot-rpi64-nvme-build)
  --env-device <path>   fw_env.config device path (default: /dev/mmcblk0)
  --env-offset-a <hex>  fw_env.config primary offset (default: 0x400000)
  --env-offset-b <hex>  fw_env.config redundant offset (default: 0x800000)
  -h, --help            Show this help

Environment:
  CROSS_COMPILE         Toolchain prefix (default: aarch64-linux-gnu-)
  UBOOT_MENDER_REPO     Source repo URL

Notes:
  - This script applies scripts/uboot/patches/uboot-mender-rpi64-nvme.patch
    to enable NVMe support and switch Mender rootfs storage path to NVMe.
  - The generated fw_env.config points to --env-device. Keep it aligned with
    your selected U-Boot environment backend.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

branch="mender-rpi-2024.04"
defconfig="rpi_arm64_defconfig"
board_name="raspberrypi_arm64_cm4_nvme"
output_dir="${repo_root}/assets"
work_dir="${repo_root}/work/uboot-rpi64-nvme-build"
env_device="/dev/mmcblk0"
env_offset_a="0x400000"
env_offset_b="0x800000"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
repo_url="${UBOOT_MENDER_REPO:-https://github.com/mendersoftware/uboot-mender.git}"

while (("$#")); do
    case "$1" in
        --branch)
            branch="${2}"
            shift 2
            ;;
        --defconfig)
            defconfig="${2}"
            shift 2
            ;;
        --board-name)
            board_name="${2}"
            shift 2
            ;;
        --output-dir)
            output_dir="${2}"
            shift 2
            ;;
        --work-dir)
            work_dir="${2}"
            shift 2
            ;;
        --env-device)
            env_device="${2}"
            shift 2
            ;;
        --env-offset-a)
            env_offset_a="${2}"
            shift 2
            ;;
        --env-offset-b)
            env_offset_b="${2}"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unsupported option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

patch_file="${script_dir}/patches/uboot-mender-rpi64-nvme.patch"
if [ ! -f "${patch_file}" ]; then
    echo "Missing patch file: ${patch_file}" >&2
    exit 1
fi

mkdir -p "${work_dir}" "${output_dir}"
src_dir="${work_dir}/uboot-mender"

rm -rf "${src_dir}"
git clone --depth 1 --branch "${branch}" "${repo_url}" "${src_dir}"

git -C "${src_dir}" apply "${patch_file}"

export ARCH=aarch64
export CROSS_COMPILE="${cross_compile}"
"${CROSS_COMPILE}gcc" --version >/dev/null

make -C "${src_dir}" "${defconfig}"
make -C "${src_dir}" -j"$(nproc)"
make -C "${src_dir}" -j"$(nproc)" envtools

if ! grep -q '^CONFIG_NVME=y' "${src_dir}/.config"; then
    echo "CONFIG_NVME is missing in .config after build setup" >&2
    exit 1
fi
if ! grep -q '^CONFIG_CMD_NVME=y' "${src_dir}/.config"; then
    echo "CONFIG_CMD_NVME is missing in .config after build setup" >&2
    exit 1
fi
if ! grep -q '^CONFIG_NVME_PCI=y' "${src_dir}/.config"; then
    echo "CONFIG_NVME_PCI is missing in .config after build setup" >&2
    exit 1
fi

version="${branch#mender-rpi-}"
tarball="${board_name}-${version}.tar.gz"
pkg_dir="${work_dir}/integration-binaries"
rm -rf "${pkg_dir}"
mkdir -p "${pkg_dir}"

cp "${src_dir}/u-boot.bin" "${pkg_dir}/"
cp "${src_dir}/tools/env/fw_printenv" "${pkg_dir}/"

cat > "${pkg_dir}/fw_env.config" <<EOF
${env_device} ${env_offset_a} 0x4000
${env_device} ${env_offset_b} 0x4000
EOF

git -C "${src_dir}" log --graph --pretty=oneline -15 > "${pkg_dir}/uboot-git-log.txt"

(cd "${pkg_dir}" && tar czvf "${output_dir}/${tarball}" ./*)

echo "Generated: ${output_dir}/${tarball}"
echo "Copy or keep this file in assets/ and use configs/local/cm4_nvme_trixie_64_ab6gb_config"
