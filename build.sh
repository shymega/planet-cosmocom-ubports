#!/bin/bash
set -xe

OUT="$(realpath "$1" 2>/dev/null || echo 'out')"
mkdir -p "$OUT"

TMP=$(mktemp -d)
HERE=$(pwd)
SCRIPT="$(dirname "$(realpath "$0")")"/build

mkdir "${TMP}/system"
mkdir "${TMP}/partitions"

source "${HERE}/deviceinfo"

case $deviceinfo_arch in
    "armhf") RAMDISK_ARCH="armhf";;
    "aarch64") RAMDISK_ARCH="arm64";;
    "x86") RAMDISK_ARCH="i386";;
esac

TMPDOWN=$(mktemp -d)
cd "$TMPDOWN"
    git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b pie-gsi --depth 1
    GCC_PATH="$TMPDOWN/aarch64-linux-android-4.9"
    if [ -n "$deviceinfo_kernel_clang_compile" ] && $deviceinfo_kernel_clang_compile; then
        git clone https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 -b pie-gsi --depth 1
        CLANG_PATH="$TMPDOWN/linux-x86/clang-4691093"
    fi
    git clone "$deviceinfo_kernel_source" -b $deviceinfo_kernel_source_branch --depth 1

    curl --location --output halium-boot-ramdisk.img \
        "https://github.com/halium/initramfs-tools-halium/releases/download/continuous/initrd.img-touch-${RAMDISK_ARCH}"
    
    if [ -n "$deviceinfo_kernel_apply_overlay" ] && $deviceinfo_kernel_apply_overlay; then
        git clone https://android.googlesource.com/platform/system/libufdt -b pie-gsi --depth 1
        git clone https://android.googlesource.com/platform/external/dtc -b pie-gsi --depth 1
    fi
    ls .
cd "$HERE"

if [ -n "$deviceinfo_kernel_apply_overlay" ] && $deviceinfo_kernel_apply_overlay; then
    "$SCRIPT/build-ufdt-apply-overlay.sh" "${TMPDOWN}"
fi

sed -i -e "s/extern test_right_usb/extern int test_right_usb/g" "$TMPDOWN/cosmo-linux-kernel-4.4/drivers/usb/gadget/configfs.c"
sed -i -e 's/printk("===zhaolong====CC1/printk("%s===zhaolong====CC1/g' "$TMPDOWN/cosmo-linux-kernel-4.4/drivers/misc/mediatek/usb_c/fusb302/usb_typec.c"

if [ -n "$deviceinfo_kernel_clang_compile" ] && $deviceinfo_kernel_clang_compile; then
    CC=clang \
    CLANG_TRIPLE=${deviceinfo_arch}-linux-gnu- \
    PATH="$CLANG_PATH/bin:$GCC_PATH/bin:${PATH}" \
    "$SCRIPT/build-kernel.sh" "${TMPDOWN}" "${TMP}/system"
else
    PATH="$GCC_PATH/bin:${PATH}" \
    "$SCRIPT/build-kernel.sh" "${TMPDOWN}" "${TMP}/system"
fi

"$SCRIPT/make-bootimage.sh" "${TMPDOWN}/KERNEL_OBJ" "${TMPDOWN}/halium-boot-ramdisk.img" "${TMP}/partitions/boot.img"

cp -av overlay/* "${TMP}/"
"$SCRIPT/build-tarball-mainline.sh" cosmocom "${OUT}" "${TMP}"

rm -r "${TMP}"
rm -r "${TMPDOWN}"

echo "done"

