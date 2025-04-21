#!/bin/bash

img=plucky-preinstalled-server-arm64.img
boards=(hikey960 jetson-nano soquartz turing-rk1 bananapi-cm4)

declare -A boards_dts=(
  [hikey960]="hisilicon/hi3660-hikey960.dts"
  [jetson-nano]="nvidia/tegra210-p3450-0000.dts"
  [soquartz]="rockchip/rk3566-soquartz-cm4.dts"
  [turing-rk1]="rockchip/rk3588-turing-rk1.dts"
  [bananapi-cm4]="amlogic/meson-g12b-bananapi-cm4-cm4io.dts"
)

declare -A boards_cmd=(
  [hikey960]="console=ttyAMA6,115200n8"
  [jetson-nano]="console=ttyS0,115200n8"
  [soquartz]="console=ttyS02,1500000n8"
  [turing-rk1]="console=ttyS02,1500000n8"
  [bananapi-cm4]="console=ttyAML0,115200n8"
)

check_deps () {
    echo "Checking dependencies"
    for dep in aarch64-linux-gnu-gcc qemu-aarch64-static makeself pip3
    do
      [[ $(which $dep 2>/dev/null) ]] || { echo "Please install $dep ";exit 1; }
    done

    for pylib in pyelftools
    do
      [[ $(pip3 list | grep -w $pylib 2>/dev/null) ]] || { echo "Please install python3 package $pylib ";exit 1; }
    done
}

make_dtb () {
    echo "Making device tree blobs"
    cd source/linux
    export ARCH=arm64 
    export CROSS_COMPILE=aarch64-linux-gnu-
    git apply ../../patch/linux/*.patch
    make defconfig
    make dtbs
    for board in ${boards[@]}; do
        board_dtb="${boards_dts[${board}]}"
        board_dtb="${board_dtb%.*}.dtb"
        cp arch/arm64/boot/dts/${board_dtb} ../../cache/${board}
    done
    git reset --hard
    git clean -f -d
    unset ARCH
    unset CROSS_COMPILE
    cd ../..
}

make_uboot () {
    echo "Making u-boot binaries"
    cd source/u-boot
    uboot_version=$(git tag --points-at HEAD)
    export CROSS_COMPILE=aarch64-linux-gnu-
    # hikey960
    make hikey960_defconfig
    make -j$(nproc)
    cp u-boot.bin ../../cache/hikey960/
    git reset --hard
    git clean -f -d
    # jetson-nano
    git apply ../../patch/u-boot/jetson-nano/*.patch
    make p3450-0000_defconfig
    make -j$(nproc)
    cp u-boot.bin ../../cache/jetson-nano/
    git reset --hard
    git clean -f -d
    # soquartz
    export ROCKCHIP_TPL="$(ls ../rkbin/bin/rk35/rk3566_ddr_1056MHz_v*.bin | sort | tail -n1)"
    export BL31="$(ls ../rkbin/bin/rk35/rk3568_bl31_v*.elf | sort | tail -n1)"
    make soquartz-cm4-rk3566_defconfig
    make -j$(nproc)
    cp u-boot-rockchip.bin ../../cache/soquartz/
    git reset --hard
    git clean -f -d
    unset ROCKCHIP_TPL
    unset BL31
    # turing-rk1
    export ROCKCHIP_TPL="$(ls ../rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v*.bin | sort | tail -n1)"
    export BL31="$(ls ../rkbin/bin/rk35/rk3588_bl31_v*.elf | sort | tail -n1)"
    make turing-rk1-rk3588_defconfig
    make -j$(nproc)
    cp u-boot-rockchip.bin ../../cache/turing-rk1/
    git reset --hard
    git clean -f -d
    unset ROCKCHIP_TPL
    unset BL31
    # bananapi-cm4
    git apply ../../patch/u-boot/bananapi-cm4/*.patch
    make bananapi-cm4-cm4io_defconfig
    make -j$(nproc)
    cp u-boot.bin ../../cache/bananapi-cm4/
    git reset --hard
    git clean -f -d
    #
    unset CROSS_COMPILE
    cd ../..

    echo "Making u-boot images"
    # soquartz
    fallocate -l 17M cache/soquartz/sdcard.img
    dd if=cache/soquartz/u-boot-rockchip.bin of=cache/soquartz/sdcard.img conv=fsync,notrunc seek=64 
    xz --compress --threads=0 cache/soquartz/sdcard.img
    mv -f cache/soquartz/sdcard.img.xz output/u-boot-${uboot_version}-soquartz.img.xz
    # turing-rk1
    fallocate -l 17M cache/turing-rk1/sdcard.img
    dd if=cache/turing-rk1/u-boot-rockchip.bin of=cache/turing-rk1/sdcard.img conv=fsync,notrunc seek=64 
    xz --compress --threads=0 cache/turing-rk1/sdcard.img
    mv -f cache/turing-rk1/sdcard.img.xz output/u-boot-${uboot_version}-turing-rk1.img.xz
    # bananapi-cm4
    cd source/amlogic-boot-fip
    ./build-fip.sh bananapi-cm4io ../../cache/bananapi-cm4/u-boot.bin ../../cache/bananapi-cm4
    git reset --hard
    git clean -f -d
    cd ../..
    fallocate -l 17M cache/bananapi-cm4/sdcard.img
    dd if=cache/bananapi-cm4/u-boot.bin.sd.bin of=cache/bananapi-cm4/sdcard.img conv=fsync,notrunc bs=512 skip=1 seek=1
    dd if=cache/bananapi-cm4/u-boot.bin.sd.bin of=cache/bananapi-cm4/sdcard.img conv=fsync,notrunc bs=1 count=440
    xz --compress --threads=0 cache/bananapi-cm4/sdcard.img
    mv -f cache/bananapi-cm4/sdcard.img.xz output/u-boot-${uboot_version}-bananapi-cm4.img.xz

    echo "Making u-boot flashers"
    # hikey960
    mkdir -p cache/hikey960/run
    cd source/arm-trusted-firmware
    export CROSS_COMPILE=aarch64-linux-gnu-
    make all fip PLAT=hikey960 BL33=../../cache/hikey960/u-boot.bin SCP_BL2=../edk2-non-osi/Platform/Hisilicon/HiKey960/lpm3.img
    cp build/hikey960/release/bl2.bin ../../cache/hikey960/run/l-loader.bin
    cp build/hikey960/release/fip.bin ../../cache/hikey960/run/
    git reset --hard
    git clean -f -d
    unset CROSS_COMPILE
    cd ../..

    cat > cache/hikey960/run/flash.sh <<EOF
#!/bin/bash

echo "Please put the board into recovery mode"
read -p "Press enter to continue"
echo "Flashing u-boot image"
sudo fastboot flash fastboot l-loader.bin
sudo fastboot flash fip fip.bin
EOF
    chmod +x cache/hikey960/run/flash.sh
    makeself cache/hikey960/run output/u-boot-${uboot_version}-hikey960.run "HiKey960 U-Boot flasher" ./flash.sh

    # jetson-nano
    mkdir -p cache/jetson-nano/run
    cp cache/jetson-nano/u-boot.bin cache/jetson-nano/run/
    cat > cache/jetson-nano/run/flash.sh <<EOF
#!/bin/bash

echo "Please put the board into recovery mode"
read -p "Press enter to continue"
echo "Flashing u-boot image"
wget -nc https://developer.nvidia.com/embedded/l4t/r32_release_v7.1/t210/jetson-210_linux_r32.7.1_aarch64.tbz2
echo Extracting jetson-210_linux_r32.7.1_aarch64.tbz2
tar xf jetson-210_linux_r32.7.1_aarch64.tbz2
docker pull nvcr.io/nvidia/jetson-linux-flash-x86:r35.4.1
docker run -t --privileged --net=host -v /dev/bus/usb:/dev/bus/usb -v ./:/workspace -w /workspace/Linux_for_Tegra nvcr.io/nvidia/jetson-linux-flash-x86:r35.4.1 bash ./flash.sh -K ../u-boot.bin --no-root-check p3448-0000-max-spi external
EOF
    chmod +x cache/jetson-nano/run/flash.sh
    makeself cache/jetson-nano/run output/u-boot-${uboot_version}-jetson-nano.run "Jetson Nano U-Boot flasher" ./flash.sh
}


download_img () {
    echo "Downloading" ${img}
    mkdir -p cache/download
    cd cache/download
    wget -nc https://cdimage.ubuntu.com/ubuntu-server/daily-preinstalled/current/${img}.xz
    cd ../..
}

extract_img () {
    echo "Extracting" ${img}.xz
    cd cache/download
    xz --decompress --threads=0 --keep ${img}.xz
    cd ../..
}

open_img () {
    echo "Loop-back mounting" cache/${1}/${img}
    read img_root_dev <<<$(grep -o 'loop.p.' <<<"$(sudo kpartx -av cache/${1}/${img})")
    img_root_dev=/dev/mapper/${img_root_dev}
    mkdir -p cache/${1}/image
    sudo mount ${img_root_dev} cache/${1}/image
}

close_img () {
    sync
    unmount_safe cache/${1}/image
    sudo kpartx -d cache/${1}/${img}
}

modify_grub_img () {
    echo "Modifying image for board" ${1}
    board_dtb="$(basename ${boards_dts[${1}]})"
    board_dtb="${board_dtb%.*}.dtb"
    sudo cp cache/${1}/${board_dtb} cache/${1}/image/boot/dtb

    sudo cat > cache/${1}/60_devicetree.cfg <<EOF
# Devicetree specific Grub settings for UEFI Devicetree Images

# Set the default commandline
GRUB_CMDLINE_LINUX_DEFAULT="efi=noruntime console=tty1 console=ttyAMA0 ${boards_cmd[${1}]}"
EOF

    sudo cp cache/${1}/60_devicetree.cfg cache/${1}/image/etc/default/grub.d/

    sudo cp $(which qemu-aarch64-static) cache/${1}/image/usr/bin
    sudo mount --bind /dev cache/${1}/image/dev/
    sudo mount --bind /sys cache/${1}/image/sys/
    sudo mount --bind /proc cache/${1}/image/proc/

    sudo chroot cache/${1}/image qemu-aarch64-static /bin/bash <<"EOT"
PATH=/usr/bin:/usr/sbin
update-grub
exit
EOT

    unmount_safe cache/${1}/image/dev/
    unmount_safe cache/${1}/image/sys/
    unmount_safe cache/${1}/image/proc/
    sudo rm cache/${1}/image/usr/bin/qemu-aarch64-static
}

modify_img () {
    for board in ${boards[@]}; do
        cp cache/download/${img} cache/${board}/
        open_img ${board}
        modify_grub_img ${board}
        close_img ${board}

        echo "Recompresssing" cache/${board}/${img}
        xz --compress --threads=0 cache/${board}/${img}

        echo "Moving to" output/${img%.*}-${board}.img.xz
        mv -f cache/${board}/${img}.xz output/${img%.*}-${board}.img.xz
    done
}


unmount_safe () {
    until sudo umount ${1}
    do
        sleep 1
        echo "Retrying unmounting" ${1}
    done
}

mkdir -p output

check_deps

for board in ${boards[@]}; do
    mkdir -p cache/${board}
done

make_uboot
make_dtb

download_img
extract_img
modify_img