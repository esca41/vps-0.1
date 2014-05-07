#!/bin/sh

set -e

# build_zfs.sh ./image.cfg
# example: ./build_img.sh /tmp/test.qcow2 image.cfg

LOG="${1%%.cfg}.log"

source "$1"

if [ ! -f "lib/${CFG_INSTALL}.sh" ]; then
	echo "No distro found: ${CFG_INSTALL}"
fi

# generate image

PART_UUID=`uuidgen`
echo "=UUID=$PART_UUID"

echo '[1/10] Partitioning virtual disk'
zfs create -s -b 2048 -V "$CFG_SIZE" "zp/vol/${PART_UUID}"

DEVICE_SYM="/dev/zp/vol/${PART_UUID}"
DEVICE=`readlink -f "${DEVICE_SYM}"`
TARGET="/mnt/${PART_UUID}"

echo -e 'o\nn\np\n1\n\n+100M\nn\np\n2\n\n+1G\nn\np\n3\n\n\nt\n2\n82\nw' | fdisk -b 2048 "${DEVICE}" >>"$LOG" 2>&1
#sgdisk -a 2048 -o -n 1::2M -n 2::100M -n 3::1G -n 4:: -t 1:ef02 -t 2:8300 -t 3:8200 -t 4:8300 "${DEVICE}" >>"$LOG" 2>&1

echo '[2/10] Formatting disk'

mkfs.ext2 "${DEVICE}p1" >>"$LOG" 2>&1
mkswap "${DEVICE}p2" >>"$LOG" 2>&1
mkfs.ext3 -b 2048 "${DEVICE}p3" >>"$LOG" 2>&1

echo '[3/10] Preparing for OS install'

mkdir -p "$TARGET"
mount "${DEVICE}p3" "$TARGET"
mkdir -p "${TARGET}/boot"
mount "${DEVICE}p1" "${TARGET}/boot"

echo '[4/10] Installing OS'

source "lib/${CFG_INSTALL}.sh"

echo '[6/10] Finishing image'

HAS_AUTORUN="no"
if [ -f "${TARGET}/autorun.sh" ]; then
	HAS_AUTORUN="yes"
fi

cat /proc/mounts | grep "${PART_UUID}" | awk '{ print $2 }' | sort -r | xargs umount
sync
rmdir "${TARGET}"
qemu-nbd -d "${DEVICE}" >>"$LOG" 2>&1

if [ $HAS_AUTORUN = "yes" ]; then
	echo '[7/10] Finalizing installation'
	/usr/bin/qemu-kvm -M pc-i440fx-1.5 -enable-kvm -m 512 -smp 1,sockets=1,cores=1,threads=1 \
	-name "autolive_install" -uuid "9B5B5C6A-6C0A-4368-B262-3CFBD525CE55" -nodefconfig -nodefaults \
	-rtc base=utc -boot order=dc,menu=on \
	-device ahci,id=ahci0,bus=pci.0,addr=0x4 \
	-drive file="${FILE}",if=none,id=drive-ahci0-0-0,format=qcow2 \
	-device ide-drive,bus=ahci0.0,drive=drive-ahci0-0-0,id=ahci0-0-0 \
	-drive file=/home/vps/iso/autolive.iso,if=none,media=cdrom,id=drive-ide0-1-0,readonly=on,format=raw \
	-device ide-drive,bus=ide.1,unit=0,drive=drive-ide0-1-0,id=ide0-1-0 \
	-usb -vnc none -vga cirrus -device virtio-balloon-pci,id=balloon0,bus=pci.0,addr=0x5
fi

echo '[8/10] Running checks'

