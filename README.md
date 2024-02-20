# ubuntu-devicetree

> [!WARNING]
> Prerelease

This project modifies standard Ubuntu Preinstalled Server Arm64 UEFI images to boot via a devicetree blob, allowing some single-board computers to work properly.
To ensure compatibility with updates most of the Ubuntu distribution and the kernel stay unmodified, only a devicetree blob is added and the GRUB boot loader configuration is slighly modified.

The intended scenario is to flash the UEFI + devicetree Ubuntu image to a NVME drive and to flash a EFI capable U-Boot boot loader to SD card/eMMC/SPI.
For convenience a up-to-date mainline U-Boot image for SD cards/eMMC is provided. 


| SBC                | Ubuntu Image | U-Boot Image | U-Boot Flasher | 
| ------------------ |:------------:| ------------:| --------------:|
| PINE64 SOQuartz    | yes          | yes          | no             | 
| NVIDIA Jetson Nano | yes          | no           | yes [^1]       | 
| 96Boards HiKey960  | yes          | no           | wip            | 


[^1]: Small patch to allow NVME boot included