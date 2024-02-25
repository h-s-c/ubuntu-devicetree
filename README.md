# ubuntu-devicetree

> [!WARNING]
> Prerelease

### Image download
[Latest release](https://github.com/h-s-c/ubuntu-devicetree/releases/tag/latest)

### Overview
This project modifies standard Ubuntu Preinstalled Server Arm64 UEFI images  
to boot via devicetree blobs to allow some single-board computers to work properly.  
To ensure compatibility with updates most of the Ubuntu distribution and the kernel stay unmodified.  
Only a devicetree blob is added and the GRUB boot loader configuration is slighly modified.  

The intended use case is to flash the UEFI + devicetree Ubuntu image to a NVME drive  
and to flash an EFI capable U-Boot boot loader to SD card/eMMC/SPI.  
For convenience an appropiate mainline U-Boot image is provided.  

| Supported SBC       | Ubuntu Image       | U-Boot Image       | U-Boot Flasher          |
| ------------------- | -------------      | -------------      | ---------------         |
| PINE64 SOQuartz     | :heavy_check_mark: | :heavy_check_mark: | :x:                     |
| NVIDIA Jetson Nano  | :heavy_check_mark: | :x:                | :heavy_check_mark:      |
| 96Boards HiKey960   | :heavy_check_mark: | :x:                | :heavy_check_mark:      |
