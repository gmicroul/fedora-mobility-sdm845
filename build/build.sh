#!/usr/bin/env bash
set -uexo pipefail

cd $(dirname $0)
pwd
mkdir -p output/esp.old output/esp.new output/artifacts

sudo kiwi-ng --type=oem --profile=SDM845-Disk --kiwi-file=Fedora-Mobility.kiwi --color-output system build --description="./" --target-dir="./output"

sudo kpartx -vafs ./output/Fedora-Mobility.aarch64-Rawhide.raw

sudo dd if=/dev/mapper/loop0p1 of=output/efipart.vfat bs=1M
sudo dd if=/dev/mapper/loop0p2 of=output/artifacts/Fedora-Mobility-Remix-SDM845-boot.raw bs=1M
sudo dd if=/dev/mapper/loop0p3 of=output/artifacts/Fedora-Mobility-Remix-SDM845-root.raw bs=1M

# the esp that kiwi generated for us has the wrong sector size, so we recreate it
VOLID=$(file output/efipart.vfat | grep -Eo "serial number 0x.{8}" | cut -d\  -f3)

truncate -s 268435456 output/artifacts/Fedora-Mobility-Remix-SDM845-esp.raw
mkfs.vfat -F 32 -S 4096 -n EFI -i "$VOLID" output/artifacts/Fedora-Mobility-Remix-SDM845-esp.raw

sudo mount -o loop output/efipart.vfat output/esp.old
sudo mount -o loop output/artifacts/Fedora-Mobility-Remix-SDM845-esp.raw output/esp.new

sudo cp -a output/esp.old/. output/esp.new/
sudo umount output/esp.old output/esp.new

# push firmware blobs into the rootfs
git clone https://gitlab.com/sdm845-mainline/firmware-oneplus-sdm845 output/firmware-oneplus-sdm845

mkdir -p output/rootfs
sudo mount -o loop,subvol=root output/artifacts/Fedora-Mobility-Remix-SDM845-root.raw output/rootfs

sudo cp --update -a output/firmware-oneplus-sdm845/usr output/rootfs/
sudo cp --update -a output/firmware-oneplus-sdm845/lib output/rootfs/usr

# hide ipa-fws.mbn. somehow loading this firmware drops the phone into crashdump mode
sudo mv output/rootfs/usr/lib/firmware/qcom/sdm845/oneplus6/ipa_fws.mbn{,.disabled}

# some blobs from firmware-oneplus-sdm845 need to be preferred over the stuff that comes from linux-firmware
sudo mv output/rootfs/usr/lib/firmware/postmarketos/* output/rootfs/usr/lib/firmware/updates
sudo rmdir output/rootfs/usr/lib/firmware/postmarketos

sudo umount output/rootfs

# clean out libdnf5 cache (800m+)
mkdir -p output/var-subvol
sudo mount -o loop,subvol=var output/artifacts/Fedora-Mobility-Remix-SDM845-root.raw output/var-subvol
sudo rm -rf output/var-subvol/cache/libdnf5/*
sudo umount output/var-subvol

gzip -9 output/artifacts/*

