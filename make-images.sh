#!/bin/bash

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
    echo "Making u-boot sdcard/emmc/spi images"
    cd source/u-boot
    export CROSS_COMPILE=aarch64-linux-gnu-
    # soquartz
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
    unset ROCKCHIP_TPL
    unset BL31
    # jetson nano
    git apply ../../patch/u-boot/jetson-nano/*.patch
    make p3450-0000_defconfig
    make -j$(nproc)
    mkdir -p ../../cache/jetson-nano
    cp u-boot.bin ../../cache/jetson-nano/
    cat > ../../cache/jetson-nano/flash.sh <<EOF
#!/bin/bash

echo "Flashing u-boot image"
wget -nc https://developer.nvidia.com/embedded/l4t/r32_release_v7.1/t210/jetson-210_linux_r32.7.1_aarch64.tbz2
echo Extracting jetson-210_linux_r32.7.1_aarch64.tbz2
tar xf jetson-210_linux_r32.7.1_aarch64.tbz2
docker pull nvcr.io/nvidia/jetson-linux-flash-x86:r35.4.1
docker run -t --privileged --net=host -v /dev/bus/usb:/dev/bus/usb -v ./:/workspace nvcr.io/nvidia/jetson-linux-flash-x86:r35.4.1 bash /workspace/Linux_for_Tegra/flash.sh -B ./u-boot.bin p3448-0000-max-spi external
EOF
    chmod +x ../../cache/jetson-nano/flash.sh
    wget -nc -P ../../cache/ https://raw.githubusercontent.com/megastep/makeself/master/makeself.sh
    wget -nc -P ../../cache/ https://raw.githubusercontent.com/megastep/makeself/master/makeself-header.sh
    chmod +x ../../cache/makeself.sh
    ../../cache/makeself.sh ../../cache/jetson-nano ../../output/u-boot-$(git tag --points-at HEAD)-jetson-nano.run "Jetson Nano U-Boot flasher" ./flash.sh
    git reset --hard
    git clean -f -d
    unset CROSS_COMPILE
    cd ../..
}


download_img () {
    echo "Downloading" ${img}
    cd cache/download
    wget -nc https://cdimage.ubuntu.com/ubuntu-server/daily-preinstalled/pending/${img}.xz
    cd ../..
}

extract_img () {
    echo "Extracting" ${img}.xz
    cd cache/download
    xz --decompress --threads=0 --keep ${img}.xz
    cd ../..
}

open_img () {
    echo "Loop-back mounting" cache/${img}
    read img_root_dev <<<$(grep -o 'loop.p.' <<<"$(kpartx -av cache/${img})")
    img_root_dev=/dev/mapper/${img_root_dev}
    mount ${img_root_dev} cache/image
}

close_img () {
    sync
    unmount_safe cache/image
    kpartx -d cache/${img}
}

modify_grub_img () {
    echo "Modifying image for board" ${1}
    board_dtb="$(basename ${boards_dts[${1}]})"
    board_dtb="${board_dtb%.*}.dtb"
    cp cache/${board_dtb} cache/image/boot/dtb

    cat > cache/image/etc/default/grub.d/60_devicetree.cfg <<EOF
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

    cp $(which qemu-aarch64-static) cache/image/usr/bin
    mount --bind /dev cache/image/dev/
    mount --bind /sys cache/image/sys/
    mount --bind /proc cache/image/proc/

    chroot cache/image qemu-aarch64-static /bin/bash <<"EOT"
PATH=/usr/bin:/usr/sbin
update-grub
exit
EOT

    unmount_safe cache/image/dev/
    unmount_safe cache/image/sys/
    unmount_safe cache/image/proc/
    rm  cache/image/usr/bin/qemu-aarch64-static
}

modify_img () {
    for board in ${boards[@]}; do
        cp cache/download/${img} cache/
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
mkdir -p cache/download
mkdir -p cache/image
mkdir -p output

make_uboot
make_dtb

download_img
extract_img
modify_img