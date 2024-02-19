[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

img=noble-preinstalled-server-arm64.img
boards=(hikey960 jetson-nano soquartz)

declare -A boards_dts=(
  [hikey960]="hisilicon/hi3660-hikey960.dts"
  [jetson-nano]="nvidia/tegra210-p3450-0000.dts"
  [soquartz]="rockchip/rk3566-soquartz-cm4.dts"
)

declare -A boards_cmd=(
  [hikey960]="console=ttyAMA6,115200n8"
  [jetson-nano]="console=ttyS0,115200n8"
  [soquartz]="console=ttyS02,1500000n8"
)

make_dtb () {
    echo "Making device tree blobs"
    cd source/linux
    export ARCH=arm64 
    export CROSS_COMPILE=aarch64-linux-gnu-
    make defconfig
    make dtbs
    for board in ${boards[@]}; do
        board_dtb="${boards_dts[${board}]}"
        board_dtb="${board_dtb%.*}.dtb"
        cp arch/arm64/boot/dts/${board_dtb} ../../cache/
    done
    git reset --hard
    git clean -f -d
    unset ARCH
    unset CROSS_COMPILE
    cd ../..
}

make_uboot () {
    echo "Making u-boot sdcard/emmc/spi image"
    cd source/u-boot
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ROCKCHIP_TPL="$(ls ../rkbin/bin/rk35/rk3566_ddr_1056MHz_v*.bin | sort | tail -n1)"
    export BL31="$(ls ../rkbin/bin/rk35/rk3568_bl31_v*.elf | sort | tail -n1)"
    make soquartz-cm4-rk3566_defconfig
    make -j$(nproc)
    fallocate -l 17M sdcard.img
    parted -s sdcard.img mklabel gpt
    parted -s sdcard.img unit s mkpart uboot 64 16MiB
    dd if=u-boot-rockchip.bin of=sdcard.img seek=64 conv=notrunc
    sync
    xz --compress --threads=0 sdcard.img
    mv -f sdcard.img.xz ../../output/u-boot-$(git tag --points-at HEAD)-soquartz.img.xz
    git reset --hard
    git clean -f -d
    unset CROSS_COMPILE
    unset ROCKCHIP_TPL
    unset BL31
    cd ../..
}


download_img () {
    echo "Downloading" ${img}
    cd download
    wget -nc https://cdimage.ubuntu.com/ubuntu-server/daily-preinstalled/pending/${img}.xz
    cd ..
}

extract_img () {
    echo "Extracting" ${img}.xz
    cd download
    xz --decompress --threads=0 --keep ${img}.xz
    cd ..
}

open_img () {
    echo "Loop-back mounting" cache/${img}
    read img_root_dev <<<$(grep -o 'loop.p.' <<<"$(kpartx -av cache/${img})")
    img_root_dev=/dev/mapper/${img_root_dev}
    mount ${img_root_dev} image
}

close_img () {
    sync
    unmount_safe image
    kpartx -d cache/${img}
}

modify_grub_img () {
    echo "Modifying image for board" ${1}
    board_dtb="$(basename ${boards_dts[${1}]})"
    board_dtb="${board_dtb%.*}.dtb"
    cp cache/${board_dtb} image/boot/dtb

    cat > image/etc/default/grub.d/60_devicetree.cfg <<EOF
# Devicetree specific Grub settings for UEFI Devicetree Images

# Set the recordfail timeout
GRUB_RECORDFAIL_TIMEOUT=0

# Do not wait on grub prompt
GRUB_TIMEOUT=0

# Set the default commandline
GRUB_CMDLINE_LINUX_DEFAULT="efi=noruntime console=tty1 console=ttyAMA0 ${boards_cmd[${1}]}"

# Set the grub console type
GRUB_TERMINAL=console
EOF

    cp $(which qemu-aarch64-static) image/usr/bin
    mount --bind /dev image/dev/
    mount --bind /sys image/sys/
    mount --bind /proc image/proc/

    chroot image qemu-aarch64-static /bin/bash <<"EOT"
PATH=/usr/bin:/usr/sbin
update-grub
exit
EOT

    unmount_safe image/dev/
    unmount_safe image/sys/
    unmount_safe image/proc/
    rm  image/usr/bin/qemu-aarch64-static
}

modify_img () {
    for board in ${boards[@]}; do
        cp download/${img} cache/
        open_img 
        modify_grub_img ${board}
        close_img

        echo "Recompresssing" cache/${img}
        xz --compress --threads=0 cache/${img}

        echo "Moving to" output/${img%.*}-${board}.img.xz
        mv -f cache/${img}.xz output/${img%.*}-${board}.img.xz
    done
}


unmount_safe () {
    until umount ${1}
    do
        sleep 1
        echo "Retrying unmounting" ${1}
    done
}

mkdir -p cache
mkdir -p download
mkdir -p image
mkdir -p output

make_uboot
make_dtb

download_img
extract_img
modify_img