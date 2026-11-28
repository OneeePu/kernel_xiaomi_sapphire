### AnyKernel3 Ramdisk Mod Script
## Sapphire / Sapphiren (Redmi Note 13 4G / NFC)

### AnyKernel setup
properties() { '
kernel.string=Sapphire ThinLTO kernel by OneeePu
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=sapphiren
device.name2=sapphire
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

### Boot partition
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# Keep the existing ramdisk untouched; only replace the kernel in the active slot.
split_boot;
flash_boot;
