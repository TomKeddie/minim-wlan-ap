. /lib/functions/system.sh

RAMFS_COPY_BIN='fw_printenv fw_setenv'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

qca_do_upgrade() {
	local tar_file="$1"

	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	local dev=$(find_mtd_chardev "0:HLOS")

	tar Oxf $tar_file ${board_dir}/kernel | mtd write - ${dev}

	if [ -n "$UPGRADE_BACKUP" ]; then
		tar Oxf $tar_file ${board_dir}/root | mtd -j "$UPGRADE_BACKUP" write - rootfs
	else
		tar Oxf $tar_file ${board_dir}/root | mtd write - rootfs
	fi
}

find_mmc_part() {
	local DEVNAME PARTNAME

	if grep -q "$1" /proc/mtd; then
		echo "" && return 0
	fi

	for DEVNAME in /sys/block/mmcblk*/mmcblk*p*; do
		PARTNAME=$(grep PARTNAME ${DEVNAME}/uevent | cut -f2 -d'=')
		[ "$PARTNAME" = "$1" ] && echo "/dev/$(basename $DEVNAME)" && return 0
	done
}

do_flash_emmc() {
	local tar_file=$1
	local emmcblock=$(find_mmc_part $2)
	local board_dir=$3
	local part=$4

	[ -z "$emmcblock" ] && {
		echo failed to find $2
		return
	}

	echo erase $4
	dd if=/dev/zero of=${emmcblock} 2> /dev/null
	echo flash $4
	tar Oxf $tar_file ${board_dir}/$part | dd of=${emmcblock}
}

emmc_do_upgrade() {
	local tar_file="$1"

	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	do_flash_emmc $tar_file '0:HLOS' $board_dir kernel
	do_flash_emmc $tar_file '0:HLOS_1' $board_dir kernel
	do_flash_emmc $tar_file 'rootfs' $board_dir root
	do_flash_emmc $tar_file 'rootfs_1' $board_dir root

	local emmcblock="$(find_mmc_part "rootfs_data")"
        if [ -e "$emmcblock" ]; then
                mkfs.ext4 -F "$emmcblock"
        fi
}

platform_check_image() {
	local magic_long="$(get_magic_long "$1")"
	board=$(board_name)
	case $board in
	cig,wf194c4|\
	cig,wf196|\
	edgecore,eap102|\
	edgecore,eap106|\
	motorola,q14|\
	tplink,ex227|\
	tplink,ex447)
		[ "$magic_long" = "73797375" ] && return 0
		;;
	esac
	return 1
}

platform_do_upgrade() {
	CI_UBIPART="rootfs"
	CI_ROOTPART="ubi_rootfs"
	CI_IPQ807X=1

	board=$(board_name)
	case $board in
	tplink,ex227)	
		qca_do_upgrade "$1"
		;;
	motorola,q14)
		emmc_do_upgrade $1
		;;
	cig,wf194c4|\
	cig,wf196|\
	tplink,ex447)
		nand_upgrade_tar "$1"
		;;
	edgecore,eap106)
		CI_UBIPART="rootfs1"
		[ "$(find_mtd_chardev rootfs)" ] && CI_UBIPART="rootfs"
		nand_upgrade_tar "$1"
		;;
	edgecore,eap102)
		if [ "$(find_mtd_chardev rootfs)" ]; then
			CI_UBIPART="rootfs"
		else
			if grep -q rootfs1 /proc/cmdline; then
				CI_UBIPART="rootfs2"
				fw_setenv active 2 || exit 1
			else
				CI_UBIPART="rootfs1"
				fw_setenv active 1 || exit 1
			fi
		fi
		nand_upgrade_tar "$1"
		;;
	esac
}
