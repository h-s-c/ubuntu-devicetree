# ubuntu-devicetree

> [!WARNING]
> Prerelease

### Image download
[Latest release](https://github.com/h-s-c/ubuntu-devicetree/releases/tag/latest)

### Overview
This script modifies standard Ubuntu Preinstalled Server UEFI images  
to allow some single-board computers to work properly.  
To ensure compatibility with updates most of the Ubuntu distribution and the kernel stay unmodified.  
Only a devicetree blob is added and the GRUB boot loader configuration is slighly modified.  

The intended use case is to flash the UEFI + devicetree Ubuntu image to a NVME drive  
and to flash an EFI capable U-Boot boot loader to SD card/eMMC/SPI.  

| Single Board Computer   | Form factor      | Ubuntu Image       |
| ----------------------- | ---------------- | -------------      |
| PINE64 SOQuartz         | Raspberry Pi CM4 | :heavy_check_mark: |
| Banana Pi BPI-CM4       | Raspberry Pi CM4 | :heavy_check_mark: |
| Radxa CM3               | Raspberry Pi CM4 | :construction:     |
| Milk-V Mars CM          | Raspberry Pi CM4 | :construction:     |
| NVIDIA Jetson Nano      | Jetson SO-DIMM   | :heavy_check_mark: |
| Turing RK1              | Jetson SO-DIMM   | :construction:     |
| 96Boards HiKey960       | 96Boards CE      | :heavy_check_mark: |
