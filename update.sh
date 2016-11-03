#!/bin/sh
# Prepare files needed for flashing a Apalis/Colibri iMX6 module
#
# inspired by meta-fsl-arm/classes/image_types_fsl.bbclass
#
# Modified by Spiri, to create a flash disk from a yocto build.
# Clone script repo into your build dir (e.g. 'build-apalis-imx6/')

# exit on error
set -e

# sometimes we need the binary echo, not the shell builtin
ECHO=`which echo`
#some distros have fs tools only in root's path
PARTED=`which parted` 2> /dev/null || true
if [ -e "$PARTED" ] ; then
	MKFSVFAT=`which mkfs.vfat`
else
	PARTED=`sudo which parted`
	MKFSVFAT=`sudo which mkfs.vfat`
fi

Flash()
{
	echo "To flash the Apalis/Colibri iMX6 module a running U-Boot is required. Boot the"
	echo "module to the U-Boot prompt and"
	echo ""
	echo "insert the SD card, USB flash drive or when using TFTP connect Ethernet only"
	echo "and enter:"
	echo "'run setupdate'"
	echo ""
	echo "then to update all components enter:"
	echo "'run update' or 'run update_it'"
	echo ""
	echo "to update a single component enter one of:"
	echo "'run update_uboot' or 'run update_uboot_it'"
	echo "'run update_kernel'"
	echo "'run update_rootfs'"
	echo ""
	echo "for 'Apalis iMX6Q 2GB IT' use the version with '_it'."
	echo ""
	echo "If you don't have a working U-Boot anymore, connect your PC to the module's USB"
	echo "client port, bring the module in the serial download mode and start the"
	echo "update.sh script with the -d option. This will copy U-Boot into the modules RAM"
	echo "and execute it."
}

Usage()
{
	echo ""
	echo "Prepares and copies files for flashing internal eMMC of Apalis/Colibri iMX6"
	echo ""
	echo "Will require a running U-Boot on the target. Either one already flashed on the"
	echo "eMMC or one copied over USB into the module's RAM"
	echo ""
	echo "-c           : split resulting rootfs into chunks usable for TFTP transmission"
	echo "-d           : use USB connection to copy/execute U-Boot to/from module's RAM"
	echo "-f           : flash instructions"
	echo "-h           : prints this message"
	echo "-o directory : output directory"
	echo ""
	echo "Example \"./update.sh -o /srv/tftp/\" copies the required files to /srv/tftp/"
	echo ""
	echo "*** For detailed recovery/update procedures, refer to the following website: ***"
        echo "http://developer.toradex.com/knowledge-base/flashing-linux-on-imx6-modules"
	echo ""
}

# initialise options
MIN_PARTITION_FREE_SIZE=100
OUT_DIR=""
ROOTFSPATH=rootfs
SPLIT=0
UBOOT_RECOVERY=0
# No devicetree by default
KERNEL_DEVICETREE=""
KERNEL_IMAGETYPE="uImage"
YOCTO_IMAGE_PATH=../tmp/deploy/images/apalis-imx6

while getopts "cdfho:" Option ; do
	case $Option in
		c)	SPLIT=1
			;;
		d)	UBOOT_RECOVERY=1
			;;
		f)	Flash
			exit 0
			;;
		h)	Usage
			# Exit if only usage (-h) was specified.
			if [ "$#" -eq 1 ] ; then
				exit 10
			fi
			exit 0
			;;
		o)	OUT_DIR=$OPTARG
			;;
	esac
done

if [ "$OUT_DIR" = "" ] && [ "$UBOOT_RECOVERY" = "0" ] ; then
	Usage
	exit 0
fi

# is OUT_DIR an existing directory?
if [ ! -d "$OUT_DIR" ] && [ "$UBOOT_RECOVERY" = "0" ] ; then
	echo "$OUT_DIR" "does not exist, exiting"
	exit 1
fi

# is there a yocto build?
if [ ! -d "$YOCTO_IMAGE_PATH" ] ; then
	echo "Yocto image not found"
	exit 1
fi

sudo rm -rf $ROOTFSPATH
mkdir $ROOTFSPATH

sudo tar --extract --gzip --file $YOCTO_IMAGE_PATH/spiri-image-apalis-imx6.tar.gz --directory $ROOTFSPATH

echo "Apalis iMX6 rootfs"
MODTYPE=apalis-imx6
# assumed minimal eMMC size [in sectors of 512]
EMMC_SIZE=$(expr 1024 \* 3500 \* 2)
IMAGEFILE=root.ext3
KERNEL_DEVICETREE="imx6q-apalis-ixora.dtb "
LOCPATH="imx_flash"
OUT_DIR="$OUT_DIR/apalis_imx6"
U_BOOT_BINARY=u-boot.imx
U_BOOT_BINARY_IT=u-boot.imx-it

BINARIES=${MODTYPE}_bin

#is only U-Boot to be copied to RAM?
if [ "$UBOOT_RECOVERY" -ge 1 ] ; then
	cd ${LOCPATH}
	#the IT timings work for all modules, so use it during recovery
	sudo ./imx_usb ../${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY_IT}
	exit 1
fi

#sanity check for awk programs
AWKTEST=`echo 100000000 | awk -v min=100 -v f=10000 '{rootfs_size=$1+f*512;rootfs_size=int(rootfs_size/1024/985); print (rootfs_size+min) }'` || true
[ "${AWKTEST}x" = "204x" ] || { echo >&2 "Program awk not available.  Aborting."; exit 1; }

#sanity check for correct untared rootfs
DEV_OWNER=`ls -ld rootfs/dev | awk '{print $3}'`
if [ "${DEV_OWNER}x" != "rootx" ]
then
	$ECHO -e "rootfs/dev is not owned by root, but it should!"
	$ECHO -e "\033[1mPlease unpack the tarball with root rights.\033[0m"
	$ECHO -e "e.g. sudo tar xjvf Apalis_iMX6_LinuxImageV2.1_20140201.tar.bz2"
	exit 1
fi

#sanity check for existence of U-Boot and kernel
[ -e ${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY} ] || { echo "${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY} does not exist"; exit 1; }
[ -e ${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY_IT} ] || { echo "${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY_IT} does not exist"; exit 1; }
[ -e ${YOCTO_IMAGE_PATH}/uImage ] || { echo "${YOCTO_IMAGE_PATH}/uImage does not exist"; exit 1; }

#sanity check for some programs
MCOPY=`sudo which mcopy`
[ "${MCOPY}x" != "x" ] || { echo >&2 "Program mcopy not available.  Aborting."; exit 1; }
sudo ${PARTED} -v >/dev/null 2>&1 || { echo >&2 "Program parted not available.  Aborting."; exit 1; }
[ "${MKFSVFAT}x" != "x" ] || { echo >&2 "Program mkfs.vfat not available.  Aborting."; exit 1; }
MKFSEXT3=`sudo which mkfs.ext3`
[ "${MKFSEXT3}x" != "x" ] || { echo >&2 "Program mkfs.ext3 not available.  Aborting."; exit 1; }
dd --help >/dev/null 2>&1 || { echo >&2 "Program dd not available.  Aborting."; exit 1; }

#make the directory with the outputfiles writable
sudo chown $USER: ${BINARIES}

#make a file with the used versions for U-Boot, kernel and rootfs
rm -f ${BINARIES}/versions.txt
touch ${BINARIES}/versions.txt
echo "Component Versions" > ${BINARIES}/versions.txt
basename "`readlink -e ${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY}`" >> ${BINARIES}/versions.txt
basename "`readlink -e ${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY_IT}`" >> ${BINARIES}/versions.txt
basename "`readlink -e ${YOCTO_IMAGE_PATH}/uImage`" >> ${BINARIES}/versions.txt
$ECHO -n "Rootfs " >> ${BINARIES}/versions.txt
grep -i qt rootfs/etc/issue >> ${BINARIES}/versions.txt

#create subdirectory for this module type
sudo mkdir -p "$OUT_DIR"

# The eMMC layout used is:
#
# boot area partition 1 aka primary eMMC boot sector:
# with U-Boot boot loader and the U-Boot environment before the configblock at
# the end of that boot area partition
#
# boot area partition 2 aka secondary eMMC boot sector:
# reserved
#
# user area aka general purpose eMMC region:
#
#    0                      -> IMAGE_ROOTFS_ALIGNMENT         - reserved (not partitioned)
#    IMAGE_ROOTFS_ALIGNMENT -> BOOT_SPACE                     - kernel and other data
#    BOOT_SPACE             -> SDIMG_SIZE                     - rootfs
#
#            4MiB               16MiB           SDIMG_ROOTFS
# <-----------------------> <----------> <---------------------->
#  ------------------------ ------------ ------------------------
# | IMAGE_ROOTFS_ALIGNMENT | BOOT_SPACE | ROOTFS_SIZE            |
#  ------------------------ ------------ ------------------------
# ^                        ^            ^                        ^
# |                        |            |                        |
# 0                      4MiB      4MiB + 16MiB              EMMC_SIZE


# Boot partition [in sectors of 512]
BOOT_START=$(expr 4096 \* 2)
# Rootfs partition [in sectors of 512]
ROOTFS_START=$(expr 20480 \* 2)
# Boot partition volume id
BOOTDD_VOLUME_ID="boot"

echo ""
echo "Creating MBR file and do the partitioning"
# Initialize a sparse file
dd if=/dev/zero of=${BINARIES}/mbr.bin bs=512 count=0 seek=${EMMC_SIZE}
${PARTED} -s ${BINARIES}/mbr.bin mklabel msdos
${PARTED} -a none -s ${BINARIES}/mbr.bin unit s mkpart primary fat32 ${BOOT_START} $(expr ${ROOTFS_START} - 1 )
# the partition spans to the end of the disk, even though the fs size will be smaller
# on the target the fs is then grown to the full size
${PARTED} -a none -s ${BINARIES}/mbr.bin unit s mkpart primary ext2 ${ROOTFS_START} $(expr ${EMMC_SIZE} \- ${ROOTFS_START} \- 1)
${PARTED} -s ${BINARIES}/mbr.bin unit s print 
# get the size of the VFAT partition
BOOT_BLOCKS=$(LC_ALL=C ${PARTED} -s ${BINARIES}/mbr.bin unit b print \
	| awk '/ 1 / { print int(substr($4, 1, length($4 -1)) / 1024) }')
# now crop the file to only the MBR size
IMG_SIZE=512
truncate -s $IMG_SIZE ${BINARIES}/mbr.bin


echo ""
echo "Creating VFAT partion image with the kernel"
rm -f ${BINARIES}/boot.vfat
${MKFSVFAT} -n "${BOOTDD_VOLUME_ID}" -S 512 -C ${BINARIES}/boot.vfat $BOOT_BLOCKS 
export MTOOLS_SKIP_CHECK=1
mcopy -i ${BINARIES}/boot.vfat -s ${YOCTO_IMAGE_PATH}/uImage ::/uImage

# Copy device tree file
COPIED=false
if test -n "${KERNEL_DEVICETREE}"; then
	for DTS_FILE in ${KERNEL_DEVICETREE}; do
		DTS_BASE_NAME=`basename ${DTS_FILE} | awk -F "." '{print $1}'`
		if [ -e "${YOCTO_IMAGE_PATH}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb" ]; then
			kernel_bin="`readlink ${YOCTO_IMAGE_PATH}/${KERNEL_IMAGETYPE}`"
			kernel_bin_for_dtb="`readlink ${YOCTO_IMAGE_PATH}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb | sed "s,$DTS_BASE_NAME,${MODTYPE},g;s,\.dtb$,.bin,g"`"
			if [ "$kernel_bin" = "$kernel_bin_for_dtb" ]; then
				mcopy -i ${BINARIES}/boot.vfat -s ${YOCTO_IMAGE_PATH}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb ::/${DTS_BASE_NAME}.dtb
				#copy also to out_dir
				sudo cp ${YOCTO_IMAGE_PATH}/${KERNEL_IMAGETYPE}-${DTS_BASE_NAME}.dtb "$OUT_DIR/${DTS_BASE_NAME}.dtb"
				COPIED=true
			fi
		fi
	done
	[ $COPIED = true ] || { echo "Did not find the devicetrees from KERNEL_DEVICETREE, ${KERNEL_DEVICETREE}.  Aborting."; exit 1; }
fi

echo ""
echo "Creating rootfs partion image"
#make the filesystem size size(rootfs used + MIN_PARTITION_FREE_SIZE)
#add about 4% to the rootfs to account for fs overhead. (/1024/985 instead of /1024/1024).
#add 512 bytes per file to account for small files
#(resize it later on target to fill the size of the partition it lives in)
NUMBER_OF_FILES=`sudo find ${ROOTFSPATH} | wc -l`
EXT_SIZE=`sudo du -DsB1 ${ROOTFSPATH} | awk -v min=$MIN_PARTITION_FREE_SIZE -v f=${NUMBER_OF_FILES} \
		'{rootfs_size=$1+f*512;rootfs_size=int(rootfs_size/1024/985); print (rootfs_size+min) }'`
rm -f ${BINARIES}/${IMAGEFILE}
sudo $LOCPATH/genext3fs.sh -d rootfs -b ${EXT_SIZE} ${BINARIES}/${IMAGEFILE} || exit 1


#copy to $OUT_DIR
sudo cp ${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY} ${YOCTO_IMAGE_PATH}/${U_BOOT_BINARY_IT} ${YOCTO_IMAGE_PATH}/uImage ${BINARIES}/mbr.bin ${BINARIES}/boot.vfat \
	${BINARIES}/${IMAGEFILE} ${BINARIES}/flash*.img ${BINARIES}/versions.txt "$OUT_DIR"
sudo rsync --progress ${BINARIES}/fwd_blk.img "$OUT_DIR/../flash_blk.img"
sudo rsync --progress ${BINARIES}/fwd_eth.img "$OUT_DIR/../flash_eth.img"
sudo rsync --progress ${BINARIES}/fwd_mmc.img "$OUT_DIR/../flash_mmc.img"
#cleanup intermediate files
sudo rm ${BINARIES}/mbr.bin ${BINARIES}/boot.vfat ${BINARIES}/${IMAGEFILE} ${BINARIES}/versions.txt

if [ "$SPLIT" -ge 1 ] ; then
sudo split -a 2 -b `expr 64 \* 1024 \* 1024` --numeric-suffixes=10 "$OUT_DIR/root.ext3" "$OUT_DIR/root.ext3-"

#transmogrify filenames to accomodate uboot hex aritmetic
set +e
sudo mkdir "$OUT_DIR/tmp"
set -e
sudo mv $OUT_DIR/root.ext3-* $OUT_DIR/tmp/
echo "moved files to tmp"

for FILE in `ls "$OUT_DIR/tmp"`
    do
        FILENUM=`printf $FILE | tail -c 2`
	FILENUMRESULT=$((($FILENUM - 10) + 16))
	echo $FILE\n
	sudo mv "$OUT_DIR/tmp/$FILE" $OUT_DIR/root.ext3-`printf "%02x" $FILENUMRESULT`
    done
sudo rmdir "$OUT_DIR/tmp"
fi
sync

sudo rm -rf $ROOTFSPATH

echo "Successfully copied data to target folder."
echo ""

Flash
