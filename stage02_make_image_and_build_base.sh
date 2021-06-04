#!/bin/bash
#
# Make disk image and build base script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022

export LC_ALL=POSIX
export PARALLEL_JOBS=4
export CONFIG_LINUX_ARCH="arm64"
export CONFIG_TARGET="aarch64-linux-gnu"
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export WORKSPACE_DIR=$PWD
export SOURCES_DIR=$WORKSPACE_DIR/src
export BUILD_DIR=$WORKSPACE_DIR/build
export SYSROOT_DIR=$WORKSPACE_DIR/sysroot
export IMAGES_DIR=$WORKSPACE_DIR/image

#Defines the default optimization flag. Use -Os if target boot disk is a microSD card else use -O2 for USB.
#The -Os makes executebels smaller but slower to execute. MicroSD cards are so slow that -Os should be faster than -O2.
export defaulOflag="-O2"

export CFLAGS=$defaulOflag
export CPPFLAGS=$defaulOflag
export CXXFLAGS=$defaulOflag

export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_STRIP_AND_DELETE_DOCS=1

#End of optional parameters
totalsteps=81
count=0

function step(){
	((count=$count+1))
	echo -e "\e[7m\e[1m>>> [$count/$1\e[0m"
	TITLE="[$count/$1"
}

function extract(){
	case $1 in
		*.tgz) tar -zxf $1 -C $2 ;;
		*.tar.gz) tar -zxf $1 -C $2 ;;
		*.tar.bz2) tar -jxf $1 -C $2 ;;
		*.tar.xz) tar -Jxf $1 -C $2 ;;
	esac
}

step "$totalsteps] Create and mount SD card image"
#Creates a empty 6000 MB unpartitioned disk image
dd if=/dev/zero of=$IMAGES_DIR/image.img bs=1M count=6000
#Setups partion table
parted $IMAGES_DIR/image.img mktable msdos
#Prepares a FAT32 partion from the first MB on image with the size of 640 MB.
#512 MB should be enough for boot but for safety add atleast 25% extra is recommend.
#The first partition has to be FAT32 as the Raspberry Pi boots the first partition and the part of the firmware that can fit on the SoC only supports FAT32.
parted $IMAGES_DIR/image.img mkpart p fat32 1 640
#Prepares a EXT4 partion from the 641 MB on image and the fill up the remaining image.
parted $IMAGES_DIR/image.img mkpart p ext4 641 100%
#Mounts all partition on image in /dev/mapper
kpartx -a $IMAGES_DIR/image.img
#Formats first partition with FAT32
mkfs.vfat /dev/mapper/loop0p1
#Formats second partition with EXT4
mkfs.ext4 /dev/mapper/loop0p2
#Mounts the EXT4 partition inside $SYSROOT_DIR
mount /dev/mapper/loop0p2 $SYSROOT_DIR
#Makes dir for mounting the FAT32 partition as boot inside the EXT4
mkdir $SYSROOT_DIR/boot
#Mounts the FAT32 partition inside $SYSROOT_DIR/boot
mount /dev/mapper/loop0p1 $SYSROOT_DIR/boot

step "$totalsteps] Create root file system directory"
mkdir -pv $SYSROOT_DIR/{boot,bin,dev,etc,lib,media,mnt,opt,proc,root,run,sbin,sys,tmp,usr}
#ln -snvf lib $SYSROOT_DIR/lib64
mkdir -pv $SYSROOT_DIR/dev/{pts,shm}
mkdir -pv $SYSROOT_DIR/etc/{network,profile.d}
mkdir -pv $SYSROOT_DIR/etc/network/{if-down.d,if-post-down.d,if-pre-up.d,if-up.d}
mkdir -pv $SYSROOT_DIR/usr/{bin,lib,sbin}
#ln -snvf lib $SYSROOT_DIR/usr/lib64
mkdir -pv $SYSROOT_DIR/var/lib

step "$totalsteps] Copy firmware from $SOURCES_DIR into $SYSROOT_DIR/boot"
cp $SOURCES_DIR/LICENCE.broadcom $SYSROOT_DIR/boot/
cp $SOURCES_DIR/bootcode.bin $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup4.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup4cd.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup4db.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup4x.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup_cd.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup_db.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/fixup_x.dat $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start4.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start4cd.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start4db.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start4x.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start_cd.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start_db.elf $SYSROOT_DIR/boot/
cp $SOURCES_DIR/start_x.elf $SYSROOT_DIR/boot/

step "$totalsteps] Basic config"
at > /etc/hosts << EOF
"127.0.0.1 localhost $(hostname)" 
::1        localhost
EOF
cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/bin/false
systemd-bus-proxy:x:72:72:systemd Bus Proxy:/:/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/bin/false
systemd-network:x:76:76:systemd Network Management:/:/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF
cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-bus-proxy:x:72:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:81:
wheel:x:97:
nogroup:x:99:
users:x:999:
EOF

step "$totalsteps] Raspberry Pi Linux Kernel"
extract $SOURCES_DIR/raspberrypi-kernel_1.20210303-1.tar.gz $BUILD_DIR
KERNEL=kernel8 make bcm2711_defconfig -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
make oldconfig ARCH=arm64 -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
make prepare ARCH=arm64 -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
make -j$PARALLEL_JOBS ARCH=arm64 Image modules dtbs -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_MOD_PATH=$SYSROOT_DIR modules_install -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
#Copy the compiled kernel and other ellements needed for boot from arch/arm64/boot to the boot dir on the SD card image
cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/Image $SYSROOT_DIR/boot/kernel8.img
cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/dts/broadcom/*.dtb $SYSROOT_DIR/boot/
mkdir $SYSROOT_DIR/boot/overlays
cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/dts/overlays/*.dtb* $SYSROOT_DIR/boot/overlays/
cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/dts/overlays/README $SYSROOT_DIR/boot/overlays/

step "$totalsteps] Raspberry Pi Linux Kernel API Headers"
#Required to be completed before the glibc step
make -j$PARALLEL_JOBS headers_check -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT_DIR/usr headers_install -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
rm -rf $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1

step "$totalsteps] man pages"
extract $SOURCES_DIR/man-pages-5.11.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/man-pages-5.11
rm -rf $BUILD_DIR/man-pages-5.11

step "$totalsteps] glibc"
extract $SOURCES_DIR/glibc-2.33.tar.xz $BUILD_DIR
#Patch from Linux from Scratch for FHS-complians.
( cd $BUILD_DIR/glibc-2.33 && patch -Np1 -i $SOURCES_DIR/glibc-2.33-fhs-1.patch )
mkdir $BUILD_DIR/glibc-2.33/glibc-build
#--enable-obsolete-rpc are need for compiling GCC.
#--enable-kernel defines minimun target Linux kernel version.c
#--disable-werror are needed else warnings make "make" fail.
#--enable-stack-protector=strong compiles glibc with extra check for buffer overflows.
#When compiling for 64-bit CPU use libc_cv_slibdir to force installing in lib instead of lib64.
( cd $BUILD_DIR/glibc-2.33/glibc-build && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/glibc-2.33/configure \
	--prefix=/usr \
	--enable-shared \
	--enable-obsolete-rpc \
	--enable-kernel=3.2 \
	--disable-werror \
	--enable-stack-protector=strong \
	--with-headers=$SYSROOT_DIR/usr/include \
	--without-selinux \
	libc_cv_slibdir=/usr/lib )
make -j$PARALLEL_JOBS -C $BUILD_DIR/glibc-2.33/glibc-build
#From Linux from Scratch: Though it is a harmless message, the install stage of Glibc will complain about the absence of /etc/ld.so.conf. Prevent this warning with:
touch $SYSROOT_DIR/etc/ld.so.conf
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR install -C $BUILD_DIR/glibc-2.33/glibc-build
#Moves files Bash needs to correct locations
mv $SYSROOT_DIR/usr/lib/ld-linux-aarch64.so.1 $SYSROOT_DIR/lib/
mv sysroot/usr/lib/libdl.so.2 sysroot/usr/lib64/
#Commads to run from Linux from Scratch:
sed '/RTLDLIST=/s@/usr@@g' -i $SYSROOT_DIR/usr/bin/ldd
cp -v $BUILD_DIR/glibc-2.33/nscd/nscd.conf $SYSROOT_DIR/etc/nscd.conf
mkdir -pv $SYSROOT_DIR/var/cache/nscd
install -v -Dm644 $BUILD_DIR/glibc-2.33/nscd/nscd.tmpfiles $SYSROOT_DIR/usr/lib/tmpfiles.d/nscd.conf
install -v -Dm644 $BUILD_DIR/glibc-2.33/nscd/nscd.service $SYSROOT_DIR/usr/lib/systemd/system/nscd.service
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR localedata/install-locales -C $BUILD_DIR/glibc-2.33/glibc-build
cat > $SYSROOT_DIR/etc/nsswitch.conf << "EOF"
#Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

 End /etc/nsswitch.conf
EOF
cat > $SYSROOT_DIR/etc/ld.so.conf << "EOF"
#Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF
rm -rf $BUILD_DIR/glibc-2.33

step "$totalsteps] Setup timezone files"
mkdir $BUILD_DIR/timezone
extract $SOURCES_DIR/tzdata2021a.tar.gz $BUILD_DIR/timezone
ZONEINFO=$SYSROOT_DIR/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}

for tz in $BUILD_DIR/timezone/etcetera $BUILD_DIR/timezone/southamerica $BUILD_DIR/timezone/northamerica $BUILD_DIR/timezone/europe $BUILD_DIR/timezone/africa $BUILD_DIR/timezone/antarctica  \
	$BUILD_DIR/timezone/asia $BUILD_DIR/timezone/australasia $BUILD_DIR/timezone/backward; do
	zic -L /dev/null -d $ZONEINFO ${tz}
	zic -L /dev/null -d $ZONEINFO/posix ${tz}
	zic -L $BUILD_DIR/timezone/leapseconds -d $ZONEINFO/right ${tz}
done
cp -v $BUILD_DIR/timezone/zone.tab $BUILD_DIR/timezone/zone1970.tab $BUILD_DIR/timezone/iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p Europe/Copenhagen
unset ZONEINFO
ln -sfv /usr/share/zoneinfo/Europe/Copenhagen $SYSROOT_DIR/etc/localtime
rm -rf $BUILD_DIR/timezone

step "$totalsteps] tcl"
extract $SOURCES_DIR/tcl8.6.11-src.tar.gz $BUILD_DIR
mkdir $BUILD_DIR/tcl8.6.11/unix/tcl-build
( cd $BUILD_DIR/tcl8.6.11/unix/tcl-build && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/tcl8.6.11/unix/configure \
	--prefix=/usr \
	--enable-64bit )
make -j$PARALLEL_JOBS -C $BUILD_DIR/tcl8.6.11/unix/tcl-build
sed -e "s|$BUILD_DIR/tcl8.6.11/unix|/usr/lib|" \
	-e "s|$BUILD_DIR/tcl8.6.11|/usr/include|"  \
	-i $BUILD_DIR/tcl8.6.11/unix/tcl-build/tclConfig.sh

sed -e "s|$BUILD_DIR/tcl8.6.11/unix/pkgs/tdbc1.1.2|/usr/lib/tdbc1.1.2|" \
	-e "s|$BUILD_DIR/tcl8.6.11/pkgs/tdbc1.1.2/generic|/usr/include|"    \
	-e "s|$BUILD_DIR/tcl8.6.11/pkgs/tdbc1.1.2/library|/usr/lib/tcl8.6|" \
	-e "s|$BUILD_DIR/tcl8.6.11/pkgs/tdbc1.1.2|/usr/include|"		\
	-i $BUILD_DIR/tcl8.6.11/unix/tcl-build/pkgs/tdbc1.1.2/tdbcConfig.sh

sed -e "s|$BUILD_DIR/tcl8.6.11/unix/pkgs/itcl4.2.1|/usr/lib/itcl4.2.1|" \
	-e "s|$BUILD_DIR/tcl8.6.11/pkgs/itcl4.2.1/generic|/usr/include|"    \
	-e "s|$BUILD_DIR/tcl8.6.11/pkgs/itcl4.2.1|/usr/include|"		\
	-i $BUILD_DIR/tcl8.6.11/unix/tcl-build/pkgs/itcl4.2.1/itclConfig.sh
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/tcl8.6.11/unix/tcl-build
#Not all needed parts of tcl gets install with the normal make install so make install-private-headers are also used.
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install-private-headers -C $BUILD_DIR/tcl8.6.11/unix/tcl-build
rm -rf $BUILD_DIR/tcl8.6.11

step "$totalsteps] binutils"
extract $SOURCES_DIR/binutils-2.36.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/binutils-2.36.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/binutils-2.36.1/configure \
	--prefix=/usr \
	--enable-gold \
	--enable-ld=default \
	--enable-plugins \
	--enable-shared \
	--enable-64-bit-bfd \
	--disable-werror \
	--with-system-zlib \
	--with-sysroot=$SYSROOT_DIR )
make -j$PARALLEL_JOBS tooldir=/usr -C $BUILD_DIR/binutils-2.36.1
make -j$PARALLEL_JOBS tooldir=/usr DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/binutils-2.36.1
rm -rf $BUILD_DIR/binutils-2.36.1

step "$totalsteps] m4"
#The latest stable version of m4 are not updated to be compile-able with the latest versions of GNUlib so latest version on https://git.savannah.gnu.org/cgit/m4.git/snapshot/m4-branch-1.4.tar.gz are needed and contains aproved comits for next update
extract $SOURCES_DIR/m4-branch-1.4.tar.gz $BUILD_DIR
#The bootstrap script ./bootstrap needs to be executed before ./configure else ./configure will fail
#CFLAGS have to be set to -O2 when compiling m4 to prevent configure to get terminated with errors. Will fail with -Os or -O3.
( cd $BUILD_DIR/m4-branch-1.4 && \
	./bootstrap && \
	automake && \
	CFLAGS="-O2 " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/m4-branch-1.4/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/m4-branch-1.4
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/m4-branch-1.4
rm -rf $BUILD_DIR/m4-branch-1.4

step "$totalsteps] ncurses"
extract $SOURCES_DIR/ncurses-6.2.tar.gz $BUILD_DIR
#The without-normal flag disables building and installing most static libraries.
#The enable-pc-files flag generates and installs .pc files for pkg-config.
#The enable-widec flag allows supporet for non 8-bit locales
( cd $BUILD_DIR/ncurses-6.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/ncurses-6.2/configure \
	--prefix=/usr \
	--mandir=/usr/share/man \
	--with-shared \
	--without-debug \
	--without-normal \
	--enable-pc-files \
	--enable-widec )
make -j$PARALLEL_JOBS -C $BUILD_DIR/ncurses-6.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/ncurses-6.2
#From Linux from Scratch: Many applications still expect the linker to be able to find non-wide-character Ncurses libraries. Trick such applications into linking with wide-character libraries by means of symlinks and linker scripts
for lib in ncurses form panel menu ; do
    rm -vf $SYSROOT_DIR/usr/lib/lib${lib}.so
    echo "INPUT(-l${lib}w)" > $SYSROOT_DIR/usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc $SYSROOT_DIR/usr/lib/pkgconfig/${lib}.pc
done
#From Linux from Scratch: Remove a static library that is not handled by configure
rm -fv $SYSROOT_DIR/usr/lib/libncurses++w.a
rm -rf $BUILD_DIR/ncurses-6.2

step "$totalsteps] bash"
extract $SOURCES_DIR/bash-5.1.tar.gz $BUILD_DIR
#From Linux From Scratch: Fix a race condition if using multiple cores
sed -i  '/^bashline.o:.*shmbchar.h/a bashline.o: ${DEFDIR}/builtext.h' $BUILD_DIR/bash-5.1/Makefile.in
#The with-installed-readline flag tells bash to use external readline version
( cd $BUILD_DIR/bash-5.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/bash-5.1/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/bash-5.1\
	--without-bash-malloc \
	--with-installed-readline )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bash-5.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/bash-5.1
rm -rf $BUILD_DIR/bash-5.1

step "$totalsteps] fish"
extract $SOURCES_DIR/fish-3.2.2.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS -C $BUILD_DIR/fish-3.2.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/fish-3.2.2
rm -rf $BUILD_DIR/fish-3.2.2

step "$totalsteps] diffutils"
extract $SOURCES_DIR/diffutils-3.7.tar.xz $BUILD_DIR
( cd $BUILD_DIR/diffutils-3.7/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/diffutils-3.7/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/diffutils-3.7
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/diffutils-3.7
rm -rf $BUILD_DIR/diffutils-3.7

step "$totalsteps] file"
extract $SOURCES_DIR/file-5.40.tar.gz $BUILD_DIR
( cd $BUILD_DIR/file-5.40/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/file-5.40/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/file-5.40
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/file-5.40
rm -rf $BUILD_DIR/file-5.40

step "$totalsteps] gawk"
extract $SOURCES_DIR/gawk-5.1.0.tar.xz $BUILD_DIR
#The sed command ensure some unneeded files are not installed.
( cd $BUILD_DIR/gawk-5.1.0/ && \
	sed -i 's/extras//' Makefile.in && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gawk-5.1.0/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk-5.1.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gawk-5.1.0
mkdir -v $SYSROOT_DIR/usr/share/doc/gawk-5.1.0
cp -v $BUILD_DIR/gawk-5.1.0/doc/{awkforai.txt,*.{eps,pdf,jpg}} $SYSROOT_DIR/usr/share/doc/gawk-5.1.0
rm -rf $BUILD_DIR/gawk-5.1.0

step "$totalsteps] findutils"
extract $SOURCES_DIR/findutils-4.8.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/findutils-4.8.0/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/findutils-4.8.0/configure \
	--prefix=/usr \
	--localstatedir=/var/lib/locate )
make -j$PARALLEL_JOBS -C $BUILD_DIR/findutils-4.8.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/findutils-4.8.0
rm -rf $BUILD_DIR/findutils-4.8.0

step "$totalsteps] grep"
extract $SOURCES_DIR/grep-3.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/grep-3.6/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/grep-3.6/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/grep-3.6
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/grep-3.6
rm -rf $BUILD_DIR/grep-3.6

step "$totalsteps] gzip"
extract $SOURCES_DIR/gzip-1.10.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gzip-1.10/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gzip-1.10/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gzip-1.10
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gzip-1.10
rm -rf $BUILD_DIR/gzip-1.10

step "$totalsteps] make"
extract $SOURCES_DIR/make-4.3.tar.gz $BUILD_DIR
( cd $BUILD_DIR/make-4.3/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/make-4.3/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/make-4.3
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/make-4.3
rm -rf $BUILD_DIR/make-4.3

step "$totalsteps] patch"
extract $SOURCES_DIR/patch-2.7.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/patch-2.7.6/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/patch-2.7.6/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/patch-2.7.6
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/patch-2.7.6
rm -rf $BUILD_DIR/patch-2.7.6

step "$totalsteps] sed"
extract $SOURCES_DIR/sed-4.8.tar.xz $BUILD_DIR
( cd $BUILD_DIR/sed-4.8/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/sed-4.8/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/sed-4.8
#Generate the HTML documentation.
make -j$PARALLEL_JOBS html -C $BUILD_DIR/sed-4.8
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/sed-4.8
#Install the HTML documentation
( cd $BUILD_DIR/sed-4.8/ && \
	install -d -m755 $SYSROOT_DIR/usr/share/doc/sed-4.8 && \
	install -m644 doc/sed.html $SYSROOT_DIR/usr/share/doc/sed-4.8 )
rm -rf $BUILD_DIR/sed-4.8

step "$totalsteps] tar"
extract $SOURCES_DIR/tar-1.34.tar.xz $BUILD_DIR
( cd $BUILD_DIR/tar-1.34/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" FORCE_UNSAFE_CONFIGURE=1 \
	$BUILD_DIR/tar-1.34/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/tar-1.34
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/tar-1.34
make doc install-html docdir=$SYSROOT_DIR/usr/share/doc/tar-1.34 -C $BUILD_DIR/tar-1.34
rm -rf $BUILD_DIR/tar-1.34

step "$totalsteps] xz"
extract $SOURCES_DIR/xz-5.2.5.tar.xz $BUILD_DIR
( cd $BUILD_DIR/xz-5.2.5/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/xz-5.2.5/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/xz-5.2.5
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/xz-5.2.5
rm -rf $BUILD_DIR/xz-5.2.5

step "$totalsteps] gettext"
extract $SOURCES_DIR/gettext-0.21.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gettext-0.21/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gettext-0.21/configure \
	--prefix=/usr \
	--disable-static \
	--docdir=/usr/share/doc/gettext-0.21 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gettext-0.21
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gettext-0.21
chmod -v 0755 $SYSROOT_DIR/usr/lib/preloadable_libintl.so
rm -rf $BUILD_DIR/gettext-0.21

step "$totalsteps] bison"
extract $SOURCES_DIR/bison-3.7.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/bison-3.7.6/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/bison-3.7.6/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/bison-3.7.6 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bison-3.7.6
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/bison-3.7.6
rm -rf $BUILD_DIR/bison-3.7.6

step "$totalsteps] perl"
extract $SOURCES_DIR/perl-5.32.1.tar.gz $BUILD_DIR
#The two commands force the perl compile process to use the installed versions of Zlib and BZip2. 
#export BUILD_ZLIB=False
#export BUILD_BZIP2=0
#All flags starting with -D and the -des flag comes from Linux from Scratch https://www.linuxfromscratch.org/lfs/view/systemd/chapter08/perl.html .
( cd $BUILD_DIR/perl-5.32.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/perl-5.32.1/Configure \
	-des \
	-Dprefix=/usr \
	-Dvendorprefix=/usr \
	-Dprivlib=/usr/lib/perl5/5.32/core_perl \
	-Darchlib=/usr/lib/perl5/5.32/core_perl \
	-Dsitelib=/usr/lib/perl5/5.32/site_perl \
	-Dsitearch=/usr/lib/perl5/5.32/site_perl \
	-Dvendorlib=/usr/lib/perl5/5.32/vendor_perl \
	-Dvendorarch=/usr/lib/perl5/5.32/vendor_perl \
	-Dman1dir=/usr/share/man/man1 \
	-Dman3dir=/usr/share/man/man3 \
	-Dpager="/usr/bin/less -isR" \
	-Duseshrplib \
	-Dusethreads )
make -j$PARALLEL_JOBS -C $BUILD_DIR/perl-5.32.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/perl-5.32.1
rm -rf $BUILD_DIR/perl-5.32.1

step "$totalsteps] Python"
extract $SOURCES_DIR/Python-3.9.4.tar.xz $BUILD_DIR
( cd $BUILD_DIR/Python-3.9.4/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/Python-3.9.4/configure \
	--prefix=/usr	\
	--enable-shared	\
	--without-ensurepip )
make -j$PARALLEL_JOBS -C $BUILD_DIR/Python-3.9.4
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/Python-3.9.4
#Unpack documentation in the correct folder. 
#tar --strip-components=1  \
#	--no-same-owner	   \
#	--no-same-permissions \
#	-C $SYSROOT_DIR/usr/share/doc/python-3.9.4/html \
#	-xvf $SOURCES_DIR/python-3.9.4-docs-html.tar.bz2
rm -rf $BUILD_DIR/Python-3.9.4

step "$totalsteps] texinfo"
extract $SOURCES_DIR/texinfo-6.7.tar.xz $BUILD_DIR
( cd $BUILD_DIR/texinfo-6.7/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/texinfo-6.7/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/texinfo-6.7
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/texinfo-6.7
make TEXMF=$SYSROOT_DIR/usr/share/texmf install-tex -C $BUILD_DIR/texinfo-6.7
rm -rf $BUILD_DIR/texinfo-6.7

step "$totalsteps] zlib"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/zlib-1.2.11/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/zlib-1.2.11/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/zlib-1.2.11
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/zlib-1.2.11
rm -rf $BUILD_DIR/zlib-1.2.11

step "$totalsteps] bzip2"
extract $SOURCES_DIR/bzip2-1.0.8.tar.gz $BUILD_DIR
#The two sed commands are from the offecial Linux from Scratch, see https://www.linuxfromscratch.org/lfs/view/systemd/chapter08/bzip2.html for reason for thier uses.
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' $BUILD_DIR/bzip2-1.0.8/Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" $BUILD_DIR/bzip2-1.0.8/Makefile
make -j$PARALLEL_JOBS -f Makefile-libbz2_so -C $BUILD_DIR/bzip2-1.0.8
make -j$PARALLEL_JOBS clean -C $BUILD_DIR/bzip2-1.0.8
make -j$PARALLEL_JOBS -C $BUILD_DIR/bzip2-1.0.8
make -j$PARALLEL_JOBS PREFIX=$SYSROOT_DIR/usr install -C $BUILD_DIR/bzip2-1.0.8
mkdir -v $SYSROOT_DIR/bin/bzip2
cp -v $BUILD_DIR/bzip2-1.0.8/bzip2-shared $SYSROOT_DIR/bin/bzip2
cp -av $BUILD_DIR/bzip2-1.0.8/libbz2.so* $SYSROOT_DIR/lib
rm -rf $BUILD_DIR/bzip2-1.0.8

step "$totalsteps] Zstd"
extract $SOURCES_DIR/zstd-1.4.9.tar.gz $BUILD_DIR
( cd $BUILD_DIR/zstd-1.4.9 && make -j$PARALLEL_JOBS -C $BUILD_DIR/zstd-1.4.9 )
make -j$PARALLEL_JOBS prefix=/usr DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/zstd-1.4.9
rm -v $SYSROOT_DIR/usr/lib/libzstd.a
mv -v $SYSROOT_DIR/usr/lib/libzstd.so.* $SYSROOT_DIR/lib
ln -sfv $SYSROOT_DIR/lib/$(readlink /usr/lib/libzstd.so) $SYSROOT_DIR/usr/lib/libzstd.so
rm -rf $BUILD_DIR/zstd-1.4.9
#Zstd gets build in parent folder. The below cleans up.
rm -rf $BUILD_DIR/dynamic
rm -rf $BUILD_DIR/static
rm $BUILD_DIR/z*
rm $BUILD_DIR/b*
rm $BUILD_DIR/c*
rm $BUILD_DIR/d*
rm $BUILD_DIR/e*
rm $BUILD_DIR/f*
rm $BUILD_DIR/h*
rm $BUILD_DIR/p*
rm $BUILD_DIR/th*
rm $BUILD_DIR/ti*
rm $BUILD_DIR/u*
rm $BUILD_DIR/x*

step "$totalsteps] iana-etc"
extract $SOURCES_DIR/iana-etc-20210304.tar.gz $BUILD_DIR
( cd $BUILD_DIR/iana-etc-20210304/ && \
	cp services protocols $SYSROOT_DIR/etc )
rm -rf $BUILD_DIR/iana-etc-20210304

step "$totalsteps] readline"
extract $SOURCES_DIR/readline-8.1.tar.gz $BUILD_DIR
( cd $BUILD_DIR/readline-8.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/readline-8.1/configure \
	--prefix=/usr \
	--disable-static \
	--with-curses \
	--docdir=/usr/share/doc/readline-8.1 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/readline-8.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/readline-8.1
rm -rf $BUILD_DIR/readline-8.1

step "$totalsteps] bc"
extract $SOURCES_DIR/bc-4.0.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/bc-4.0.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/bc-4.0.1/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bc-4.0.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/bc-4.0.1
rm -rf $BUILD_DIR/bc-4.0.1

step "$totalsteps] flex"
extract $SOURCES_DIR/flex-2.6.4.tar.gz $BUILD_DIR
( cd $BUILD_DIR/flex-2.6.4/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/flex-2.6.4/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/flex-2.6.4 \
	--disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/flex-2.6.4
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/flex-2.6.4
rm -rf $BUILD_DIR/flex-2.6.4

step "$totalsteps] expect"
extract $SOURCES_DIR/expect5.45.4.tar.gz $BUILD_DIR
#Expect are using a over 15 years old version of config.guess that does not contain a definition for 64-bit Arm CPU. 64-bit Arm where released 10 years ago.
( cd $BUILD_DIR/expect5.45.4/ && \
	mv $BUILD_DIR/expect5.45.4/tclconfig/config.guess $BUILD_DIR/expect5.45.4/tclconfig/config.guess.old &&
	cp /usr/share/automake-1.16/config.guess $BUILD_DIR/expect5.45.4/tclconfig/config.guess &&
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/expect5.45.4/configure \
	--prefix=/usr \
	--with-tcl=$SYSROOT_DIR/usr/lib64 \
	--enable-shared \
	--mandir=/usr/share/man \
	--with-tclinclude=$SYSROOT_DIR/usr/include )
make -j$PARALLEL_JOBS -C $BUILD_DIR/expect5.45.4
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/expect5.45.4
rm -rf $BUILD_DIR/expect5.45.4

step "$totalsteps] dejagnu"
extract $SOURCES_DIR/dejagnu-1.6.2.tar.gz $BUILD_DIR
( cd $BUILD_DIR/dejagnu-1.6.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/dejagnu-1.6.2/configure \
	--prefix=/usr &&
	makeinfo --html --no-split -o doc/dejagnu.html doc/dejagnu.texi &&
	makeinfo --plaintext -o doc/dejagnu.txt  doc/dejagnu.texi )
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/dejagnu-1.6.2
( cd $BUILD_DIR/dejagnu-1.6.2/ && install -v -dm755 $SYSROOT_DIR/usr/share/doc/dejagnu-1.6.2 && install -v -m644 $SYSROOT_DIR/doc/dejagnu.{html,txt} $SYSROOT_DIR/usr/share/doc/dejagnu-1.6.2 )
rm -rf $BUILD_DIR/dejagnu-1.6.2

step "$totalsteps] gmp"
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gmp-6.2.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gmp-6.2.1/configure \
	--prefix=/usr \
	--enable-cxx \
	--disable-static \
	--docdir=/usr/share/doc/gmp-6.2.1 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gmp-6.2.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gmp-6.2.1
rm -rf $BUILD_DIR/gmp-6.2.1

step "$totalsteps] mpfr"
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/mpfr-4.1.0/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/mpfr-4.1.0/configure \
	--prefix=/usr \
	--disable-static \
	--enable-thread-safe \
	--docdir=/usr/share/doc/mpfr-4.1.0 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/mpfr-4.1.0
make -j$PARALLEL_JOBS html -C $BUILD_DIR/mpfr-4.1.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/mpfr-4.1.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install-html -C $BUILD_DIR/mpfr-4.1.0
rm -rf $BUILD_DIR/mpfr-4.1.0

step "$totalsteps] mpc"
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR
( cd $BUILD_DIR/mpc-1.2.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/mpc-1.2.1/configure \
	--prefix=/usr \
	--disable-static \
	--docdir=/usr/share/doc/mpc-1.2.1 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/mpc-1.2.1
make -j$PARALLEL_JOBS html -C $BUILD_DIR/mpc-1.2.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/mpc-1.2.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install-html -C $BUILD_DIR/mpc-1.2.1
rm -rf $BUILD_DIR/mpc-1.2.1

step "$totalsteps] attr"
extract $SOURCES_DIR/attr-2.5.1.tar.gz $BUILD_DIR
( cd $BUILD_DIR/attr-2.5.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/attr-2.5.1/configure \
	--prefix=/usr \
	--disable-static \
	--sysconfdir=/etc \
	--docdir=/usr/share/doc/attr-2.5.1 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/attr-2.5.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/attr-2.5.1
cp $SYSROOT_DIR/usr/lib64/libattr.so.* $SYSROOT_DIR/lib
rm -rf $BUILD_DIR/attr-2.5.1

step "$totalsteps] acl"
extract $SOURCES_DIR/acl-2.3.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/acl-2.3.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/acl-2.3.1/configure \
	--prefix=/usr \
	--disable-static \
	--libexecdir=/usr/lib \
	--docdir=/usr/share/doc/acl-2.3.1 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/acl-2.3.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/acl-2.3.1
cp $SYSROOT_DIR/usr/lib64/libacl.so.* $SYSROOT_DIR/lib
rm -rf $BUILD_DIR/acl-2.3.1

step "$totalsteps] libcap"
extract $SOURCES_DIR/libcap-2.49.tar.xz $BUILD_DIR
#From Linux from Stratch: Prevent static libraries from being installed
sed -i '/install -m.*STA/d' $BUILD_DIR/libcap-2.49/libcap/Makefile
#When compiling libcap as 64-bit the install command will normally install lib files into lib64 folder but on the lib files are needed in the lib folder. the flag lib=lib are used to force libcap files to be installed in lib folder. 
make -j$PARALLEL_JOBS prefix=/usr lib=lib -C $BUILD_DIR/libcap-2.49
make -j$PARALLEL_JOBS prefix=/usr lib=lib DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/libcap-2.49
chmod -v 755 $SYSROOT_DIR/usr/lib/lib{cap,psx}.so.2.49
rm -rf $BUILD_DIR/libcap-2.49

step "$totalsteps] coreutils"
extract $SOURCES_DIR/coreutils-8.32.tar.xz $BUILD_DIR
#When compiling for 64-bit ARM the command SYS_getdents are called SYS_getdents64. The below find-and-replace will fix this.
filename5="$BUILD_DIR/coreutils-8.32/src/ls.c"
search5="SYS_getdents,"
replace5="SYS_getdents64,"
if [[ $search5 != "" && $replace5 != "" ]]; then
	sed -i "s/$search5/$replace5/" $filename5
fi
#Without FORCE_UNSAFE_CONFIGURE=1 this packege can not be compiled as root
#--enable-no-install-program prevents some parts from being install. Kill and uptime will come from a different packege.
( cd $BUILD_DIR/coreutils-8.32/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" FORCE_UNSAFE_CONFIGURE=1 \
	$BUILD_DIR/coreutils-8.32/configure \
	--prefix=/usr \
	--enable-no-install-program=kill,uptime )
make -j$PARALLEL_JOBS -C $BUILD_DIR/coreutils-8.32
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/coreutils-8.32
mv -v $SYSROOT_DIR/usr/bin/chroot $SYSROOT_DIR/usr/sbin
mḱdir -v $SYSROOT_DIR/usr/share/man/man8
mv -v $SYSROOT_DIR/usr/share/man/man1/chroot.1 $SYSROOT_DIR/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' $SYSROOT_DIR/usr/share/man/man8/chroot.8
rm -rf $BUILD_DIR/coreutils-8.32

step "$totalsteps] shadow"
extract $SOURCES_DIR/shadow-4.8.1.tar.xz $BUILD_DIR
#From Linux from Stratch: Disable the installation of the groups program and its man pages, as Coreutils provides a better version. Also, prevent the installation of manual pages that were already installed with man-pages
sed -i 's/groups$(EXEEXT) //' $BUILD_DIR/shadow-4.8.1/src/Makefile.in
( cd $BUILD_DIR/shadow-4.8.1/ && find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \; )
( cd $BUILD_DIR/shadow-4.8.1/ && find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \; )
( cd $BUILD_DIR/shadow-4.8.1/ && find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \; )
#Force shadow to use SHA512 for passwords and also allows for longer passwords than default
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD SHA512:' \
    -e 's:/var/spool/mail:/var/mail:'		     \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'		    \
    -i $BUILD_DIR/shadow-4.8.1/etc/login.defs
#Make it so first userid will be 1000
sed -i 's/1000/999/' $BUILD_DIR/shadow-4.8.1/etc/useradd
#Some software have hardcoded password location and usr/bin/passwd needs to exist to handel this.
touch $SYSROOT_DIR/usr/bin/passwd
#The with-group-name-max-length flag defines max characters a group name can have. User name has a 32 characters limit so we set group name to same limit.
( cd $BUILD_DIR/shadow-4.8.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/shadow-4.8.1/configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--with-group-name-max-length=32 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/shadow-4.8.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/shadow-4.8.1
rm -rf $BUILD_DIR/shadow-4.8.1

step "$totalsteps] gcc"
extract $SOURCES_DIR/gcc-11.1.0.tar.xz $BUILD_DIR
mkdir -v $BUILD_DIR/gcc-11.1.0/build
( cd $BUILD_DIR/gcc-11.1.0/build && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gcc-11.1.0/configure \
	--prefix=/usr \
	LD=ld \
	--enable-languages=c,c++ \
	--disable-multilib \
	--disable-bootstrap \
	--with-system-zlib)
make -j$PARALLEL_JOBS -C $BUILD_DIR/gcc-11.1.0/build
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gcc-11.1.0/build
#From Linux from Stratch: Add a compatibility symlink to enable building programs with Link Time Optimization (LTO)
#ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/11.1.0/liblto_plugin.so /usr/lib/bfd-plugins/
rm -rf $BUILD_DIR/gcc-11.1.0

step "$totalsteps] pkg-config"
extract $SOURCES_DIR/pkg-config-0.29.2.tar.gz $BUILD_DIR
#The with-internal-glib flag tells pkg-config to its internal glib version as the external version is not available in Linux from Stratch.
#The disable-host-tool disable the creations of undesired hard link to pkg-config.
( cd $BUILD_DIR/pkg-config-0.29.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/pkg-config-0.29.2/configure \
	--prefix=/usr \
	--with-internal-glib \
	--disable-host-tool \
	--docdir=/usr/share/doc/pkg-config-0.29.2 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/pkg-config-0.29.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/pkg-config-0.29.2
rm -rf $BUILD_DIR/pkg-config-0.29.2

step "$totalsteps] psmisc"
extract $SOURCES_DIR/psmisc-23.4.tar.xz $BUILD_DIR
( cd $BUILD_DIR/psmisc-23.4/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/psmisc-23.4/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/psmisc-23.4
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/psmisc-23.4
rm -rf $BUILD_DIR/psmisc-23.4

step "$totalsteps] expat"
extract $SOURCES_DIR/expat-2.4.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/expat-2.4.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/expat-2.4.1/configure \
	--prefix=/usr \
	--disable-static \
	--docdir=/usr/share/doc/expat-2.4.1 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/expat-2.4.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/expat-2.4.1
#Install the documentation
( cd $BUILD_DIR/expat-2.4.1/ && \
	install -v -m644 doc/*.{html,png,css} $SYSROOT_DIR/usr/share/doc/expat-2.4.1 )
rm -rf $BUILD_DIR/expat-2.4.1

step "$totalsteps] libtool"
extract $SOURCES_DIR/libtool-2.4.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libtool-2.4.6/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/libtool-2.4.6/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libtool-2.4.6
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/libtool-2.4.6
#From Linux From Scratch: Remove an useless static library
rm -fv $SYSROOT_DIR/usr/lib/libltdl.a
rm -rf $BUILD_DIR/libtool-2.4.6

step "$totalsteps] gdbm"
extract $SOURCES_DIR/gdbm-1.19.tar.gz $BUILD_DIR
#The enable-libgdbm-compat flag enables building the libgdbm compatibility library. Some packages outside of LFS may require the older DBM routines it provides.
( cd $BUILD_DIR/gdbm-1.19/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gdbm-1.19/configure \
	--prefix=/usr \
	--disable-static \
	--enable-libgdbm-compat)
make -j$PARALLEL_JOBS -C $BUILD_DIR/gdbm-1.19
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gdbm-1.19
rm -rf $BUILD_DIR/gdbm-1.19

step "$totalsteps] gperf"
extract $SOURCES_DIR/gperf-3.1.tar.gz $BUILD_DIR
( cd $BUILD_DIR/gperf-3.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gperf-3.1/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/gperf-3.1)
make -j$PARALLEL_JOBS -C $BUILD_DIR/gperf-3.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gperf-3.1
rm -rf $BUILD_DIR/gperf-3.1

step "$totalsteps] inetutils"
extract $SOURCES_DIR/inetutils-2.0.tar.xz $BUILD_DIR
#All disable flags are for disabling out of date parts of inetutils.
( cd $BUILD_DIR/inetutils-2.0/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/inetutils-2.0/configure \
	--prefix=/usr \
	--bindir=/usr/bin \
	--localstatedir=/var \
	--disable-logger \
	--disable-whois \
	--disable-rcp \
	--disable-rexec \
	--disable-rlogin \
	--disable-rsh \
	--disable-servers )
make -j$PARALLEL_JOBS -C $BUILD_DIR/inetutils-2.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/inetutils-2.0
#moves the ifconfig program to correct location.
mv -v $SYSROOT_DIR/usr/{,s}bin/ifconfig
rm -rf $BUILD_DIR/inetutils-2.0

step "$totalsteps] XML-Parser"
extract $SOURCES_DIR/XML-Parser-2.46.tar.gz $BUILD_DIR
( cd $BUILD_DIR/XML-Parser-2.46/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	perl $BUILD_DIR/XML-Parser-2.46/Makefile.PL )
make -j$PARALLEL_JOBS -C $BUILD_DIR/XML-Parser-2.46
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/XML-Parser-2.46
rm -rf $BUILD_DIR/XML-Parser-2.46

step "$totalsteps] intltool"
extract $SOURCES_DIR/intltool-0.51.0.tar.gz $BUILD_DIR
#The command below fix a warning that is caused by perl-5.22 and later.
sed -i 's:\\\${:\\\$\\{:' $BUILD_DIR/intltool-0.51.0/intltool-update.in
( cd $BUILD_DIR/intltool-0.51.0/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/intltool-0.51.0/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/intltool-0.51.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/intltool-0.51.0
#Below install docs.
( cd $BUILD_DIR/intltool-0.51.0/ && \
	install -v -Dm644 doc/I18N-HOWTO $SYSROOT_DIR/usr/share/doc/intltool-0.51.0/I18N-HOWTO )
rm -rf $BUILD_DIR/intltool-0.51.0

step "$totalsteps] autoconf"
extract $SOURCES_DIR/autoconf-2.71.tar.xz $BUILD_DIR
( cd $BUILD_DIR/autoconf-2.71/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/autoconf-2.71/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/autoconf-2.71
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/autoconf-2.71
rm -rf $BUILD_DIR/autoconf-2.71

step "$totalsteps] automake"
extract $SOURCES_DIR/automake-1.16.3.tar.xz $BUILD_DIR
( cd $BUILD_DIR/automake-1.16.3/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/automake-1.16.3/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/automake-1.16.3 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/automake-1.16.3
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/automake-1.16.3
rm -rf $BUILD_DIR/automake-1.16.3

step "$totalsteps] kmod"
extract $SOURCES_DIR/kmod-28.tar.xz $BUILD_DIR
#The with-* flags enabled support for compressed kernel modules
( cd $BUILD_DIR/kmod-28/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/kmod-28/configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--with-xz \
	--with-zstd \
	--with-zlib )
make -j$PARALLEL_JOBS -C $BUILD_DIR/kmod-28
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/kmod-28
#From Linus from scratch: Install the package and create symlinks for compatibility with Module-Init-Tools (the package that previously handled Linux kernel modules)
#for target in depmod insmod lsmod modinfo modprobe rmmod; do
#	ln -sfv ../bin/kmod /sbin/$target
#done
#ln -sfv kmod /bin/lsmod
rm -rf $BUILD_DIR/kmod-28

step "$totalsteps] Libelf from elfutils"
extract $SOURCES_DIR/elfutils-0.183.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/elfutils-0.183/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/elfutils-0.183/configure \
	--prefix=/usr \
	--disable-debuginfod \
	--enable-libdebuginfod=dummy )
make -j$PARALLEL_JOBS -C $BUILD_DIR/elfutils-0.183
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR libelf install -C $BUILD_DIR/elfutils-0.183
( cd $BUILD_DIR/elfutils-0.183/ && \
	install -vm644 config/libelf.pc $SYSROOT_DIR/usr/lib/pkgconfig )
#rm $SYSROOT_DIR/usr/lib/libelf.a
rm -rf $BUILD_DIR/elfutils-0.183

step "$totalsteps] libffi-3.3"
extract $SOURCES_DIR/libffi-3.3.tar.gz $BUILD_DIR
#--with-gcc-arch=native should force using correct compiler settings for some systems
( cd $BUILD_DIR/libffi-3.3/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/libffi-3.3/configure \
	--prefix=/usr \
	--disable-static \
	--with-gcc-arch=native )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libffi-3.3
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/libffi-3.3
rm -rf $BUILD_DIR/libffi-3.3

step "$totalsteps] openssl"
extract $SOURCES_DIR/openssl-1.1.1k.tar.gz $BUILD_DIR
( cd $BUILD_DIR/openssl-1.1.1k/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/openssl-1.1.1k/config \
	--prefix=/usr \
	--openssldir=/etc/ssl \
	--libdir=lib \
	shared \
	zlib-dynamic )
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1k
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' $BUILD_DIR/openssl-1.1.1k/Makefile
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR MANSUFFIX=ssl install -C $BUILD_DIR/openssl-1.1.1k
#renames docs directory for consistensy with other packages
mv -v $SYSROOT_DIR/usr/share/doc/openssl $SYSROOT_DIR/usr/share/doc/openssl-1.1.1k
#install additional docs that where not installed with make install
cp -vfr $BUILD_DIR/openssl-1.1.1k/doc/* $SYSROOT_DIR/usr/share/doc/openssl-1.1.1k
rm -rf $BUILD_DIR/openssl-1.1.1k

step "$totalsteps] ninja-1.10.2"
extract $SOURCES_DIR/ninja-1.10.2.tar.gz $BUILD_DIR
( cd $BUILD_DIR/ninja-1.10.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	python3 $BUILD_DIR/ninja-1.10.2/configure.py \
	--bootstrap && \
	install -vm755 ninja $SYSROOT_DIR/usr/bin/
	install -vDm644 misc/bash-completion $SYSROOT_DIR/usr/share/bash-completion/completions/ninja
	install -vDm644 misc/zsh-completion  $SYSROOT_DIR/usr/share/zsh/site-functions/_ninja )
rm -rf $BUILD_DIR/ninja-1.10.2

step "$totalsteps] meson"
extract $SOURCES_DIR/meson-0.57.2.tar.gz $BUILD_DIR
( cd $BUILD_DIR/meson-0.57.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	python3 setup.py build &&
	python3 setup.py install --root=dest &&
	cp -rv dest/* $SYSROOT_DIR &&
	install -vDm644 data/shell-completions/bash/meson $SYSROOT_DIR/usr/share/bash-completion/completions/meson &&
	install -vDm644 data/shell-completions/zsh/_meson $SYSROOT_DIR/usr/share/zsh/site-functions/_meson )
rm -rf $BUILD_DIR/meson-0.57.2

step "$totalsteps] check"
extract $SOURCES_DIR/check-0.15.2.tar.gz $BUILD_DIR
( cd $BUILD_DIR/check-0.15.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/check-0.15.2/configure \
	--prefix=/usr \
	--disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/check-0.15.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR docdir=$SYSROOT_DIR/usr/share/doc/check-0.15.2 install -C $BUILD_DIR/check-0.15.2
rm -rf $BUILD_DIR/check-0.15.2

step "$totalsteps] groff"
extract $SOURCES_DIR/groff-1.22.4.tar.gz $BUILD_DIR
#The PAGE flag defines default page size used.
( cd $BUILD_DIR/groff-1.22.4/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" PAGE=A4 \
	$BUILD_DIR/groff-1.22.4/configure \
	--prefix=/usr )
make -j1 -C $BUILD_DIR/groff-1.22.4
make -j1 DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/groff-1.22.4
rm -rf $BUILD_DIR/groff-1.22.4

step "$totalsteps] less-581"
extract $SOURCES_DIR/less-581.tar.gz $BUILD_DIR
( cd $BUILD_DIR/less-581/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/less-581/configure \
	--prefix=/usr \
	--sysconfdir=/etc)
make -j$PARALLEL_JOBS -C $BUILD_DIR/less-581
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/less-581
rm -rf $BUILD_DIR/less-581

step "$totalsteps] iproute2"
extract $SOURCES_DIR/iproute2-5.12.0.tar.xz $BUILD_DIR
#The sed and rm commands disable unneeded elements
( cd $BUILD_DIR/iproute2-5.12.0/ && \
	sed -i /ARPD/d Makefile && \
	rm -fv man/man8/arpd.8 && \
	sed -i 's/.m_ipt.o//' tc/Makefile && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/iproute2-5.12.0/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/iproute2-5.12.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/iproute2-5.12.0
mkdir -v $SYSROOT_DIR/usr/share/doc/iproute2-5.12.0
( cd $BUILD_DIR/iproute2-5.12.0/ && cp -v COPYING README* $SYSROOT_DIR/usr/share/doc/iproute2-5.12.0 )
rm -rf $BUILD_DIR/iproute2-5.12.0

step "$totalsteps] kbd"
extract $SOURCES_DIR/kbd-2.4.0.tar.xz $BUILD_DIR
#The sed commands removed redundant program
( cd $BUILD_DIR/kbd-2.4.0/ && \
	sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure && \
	sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/kbd-2.4.0/configure \
	--prefix=/usr \
	--disable-vlock )
make -j$PARALLEL_JOBS -C $BUILD_DIR/kbd-2.4.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/kbd-2.4.0
mkdir -v $SYSROOT_DIR/usr/share/doc/kbd-2.4.0
cp -R -v $BUILD_DIR/kbd-2.4.0/docs/doc/* $SYSROOT_DIR/usr/share/doc/kbd-2.4.0
rm -rf $BUILD_DIR/kbd-2.4.0

step "$totalsteps] libpipeline"
extract $SOURCES_DIR/libpipeline-1.5.3.tar.gz $BUILD_DIR
( cd $BUILD_DIR/libpipeline-1.5.3/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/libpipeline-1.5.3/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libpipeline-1.5.3
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/libpipeline-1.5.3
rm -rf $BUILD_DIR/libpipeline-1.5.3

step "$totalsteps] man-db"
extract $SOURCES_DIR/man-db-2.9.4.tar.xz $BUILD_DIR
( cd $BUILD_DIR/man-db-2.9.4/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/man-db-2.9.4/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/man-db-2.9.4 \
	--sysconfdir=/etc \
	--disable-setuid \
	--enable-cache-owner=bin \
	--with-browser=/usr/bin/lynx \
	--with-vgrind=/usr/bin/vgrind \
	--with-grap=/usr/bin/grap )
make -j$PARALLEL_JOBS -C $BUILD_DIR/man-db-2.9.4
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/man-db-2.9.4
rm -rf $BUILD_DIR/man-db-2.9.4

step "$totalsteps] vim"
extract $SOURCES_DIR/v8.2.2799.tar.gz $BUILD_DIR
( cd $BUILD_DIR/vim-8.2.2799/ && \
	echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/vim-8.2.2799/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/vim-8.2.2799
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/vim-8.2.2799
#Some users are used to use vi as command instead vim to start vim. Below makes so both can be used
#ln -sv vim /usr/bin/vi
#for L in  /usr/share/man/{,*/}man1/vim.1; do
#    ln -sv vim.1 $(dirname $L)/vi.1
#done
#ln -sv ../vim/vim82/doc /usr/share/doc/vim-8.2.2813
rm -rf $BUILD_DIR/vim-8.2.2799

step "$totalsteps] nano"
extract $SOURCES_DIR/nano-5.6.1.tar.gz $BUILD_DIR
( cd $BUILD_DIR/nano-5.6.1/ && \
	./autogen.sh && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/nano-5.6.1/configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--enable-utf8 \
	--docdir=/usr/share/doc/nano-5.7 )
make -j$PARALLEL_JOBS -C $BUILD_DIR/nano-5.6.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/nano-5.6.1
(cd $BUILD_DIR/nano-5.6.1/ && install -v -m644 doc/{nano.html,sample.nanorc} $SYSROOT_DIR/usr/share/doc/nano-5.7 )
rm -rf $BUILD_DIR/nano-5.6.1

step "$totalsteps] systemd"
extract $SOURCES_DIR/v248.tar.gz $BUILD_DIR
#Systemd fails at make without below patch
( cd $BUILD_DIR/systemd-248/ && patch -Np1 -i $SOURCES_DIR/systemd-248-upstream_fixes-1.patch )
#Remove an unneeded group, render, from the default udev rules: 
sed -i 's/GROUP="render"/GROUP="video"/' $BUILD_DIR/systemd-248/rules.d/50-udev-default.rules.in
( cd $BUILD_DIR/systemd-248/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/systemd-248/configure --prefix=/usr \
	--sysconfdir=/etc \
	--localstatedir=/var \
	-Dblkid=true \
	-Dbuildtype=release \
	-Ddefault-dnssec=no \
	-Dfirstboot=false \
	-Dinstall-tests=false \
	-Dldconfig=false \
	-Dsysusers=false \
	-Db_lto=false \
	-Drpmmacrosdir=no \
	-Dhomed=false \
	-Duserdb=false \
	-Dman=false \
	-Dmode=release )
make -j$PARALLEL_JOBS LIBATTR=no PAM_CAP=no -C $BUILD_DIR/systemd-248
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/systemd-248
rm -rf $BUILD_DIR/systemd-248

step "$totalsteps] util-linux"
extract $SOURCES_DIR/util-linux-2.36.2.tar.xz $BUILD_DIR
( cd $BUILD_DIR/util-linux-2.36.2/ && \
	./autogen.sh && \
	CFLAGS="-Os" CPPFLAGS="" CXXFLAGS="-Os" LDFLAGS="-L$SYSROOT_DIR/usr/lib/ --static" \
	$BUILD_DIR/util-linux-2.36.2/configure \
	ADJTIME_PATH=/var/lib/hwclock/adjtime \
	--docdir=$SYSROOT_DIR/usr/share/doc/util-linux-2.36.2 \
	--disable-chfn-chsh \
	--disable-login \
	--disable-nologin \
	--disable-su \
	--disable-setpriv \
	--disable-runuser \
	--disable-pylibmount \
	--disable-static \
	--without-python \
	runstatedir=/run )
#the flag --static is need to get make install work when compiling util-linux
make -j$PARALLEL_JOBS LDFLAGS="-L$SYSROOT_DIR/usr/lib/ --static" -C $BUILD_DIR/util-linux-2.36.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/util-linux-2.36.2
rm -rf $BUILD_DIR/util-linux-2.36.2

step "$totalsteps] dbus"
extract $SOURCES_DIR/dbus-1.12.20.tar.gz $BUILD_DIR
( cd $BUILD_DIR/dbus-1.12.20/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/dbus-1.12.20/configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--localstatedir=/var \
	--disable-static \
	--disable-doxygen-docs \
	--disable-xml-docs \
	--docdir=/usr/share/doc/dbus-1.12.20 \
	--with-console-auth-dir=/run/console \
	--with-system-pid-file=/run/dbus/pid \
	--with-system-socket=/run/dbus/system_bus_socket )
make -j$PARALLEL_JOBS -C $BUILD_DIR/dbus-1.12.20
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/dbus-1.12.20
rm -rf $BUILD_DIR/dbus-1.12.20

step "$totalsteps] procps-ng-3.3.17"
extract $SOURCES_DIR/procps-ng-3.3.17.tar.xz $BUILD_DIR
( cd $BUILD_DIR/procps-3.3.17/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/procps-3.3.17/configure \
	--prefix=/usr \
	--docdir=/usr/share/doc/procps-ng-3.3.17 \
	--disable-static \
	--disable-kill \
	--with-systemd )
make -j$PARALLEL_JOBS -C $BUILD_DIR/procps-3.3.17
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/procps-3.3.17
rm -rf $BUILD_DIR/procps-3.3.17

step "$totalsteps] e2fsprogs"
extract $SOURCES_DIR/e2fsprogs-1.46.2.tar.gz $BUILD_DIR
( cd $BUILD_DIR/e2fsprogs-1.46.2/ && \
	mkdir -v build && cd build && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/e2fsprogs-1.46.2/configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--enable-elf-shlibs \
	--disable-libblkid \
	--disable-libuuid \
	--disable-uuidd \
	--disable-fsck )
make -j$PARALLEL_JOBS -C $BUILD_DIR/e2fsprogs-1.46.2/build
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/e2fsprogs-1.46.2/build
rm -fv $SYSROOT_DIR/usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
rm -rf $BUILD_DIR/e2fsprogs-1.46.2

step "$totalsteps] Setting base config"
touch $SYSROOT_DIR/var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp $SYSROOT_DIR/var/log/lastlog
chmod -v 664  $SYSROOT_DIR/var/log/lastlog
chmod -v 600  $SYSROOT_DIR/var/log/btmp
#bzip2
ln -sv $SYSROOT_DIR/lib/libbz2.so.1.0 $SYSROOT_DIR/usr/lib/libbz2.so
rm -v $SYSROOT_DIR/usr/bin/{bunzip2,bzcat,bzip2}
ln -sv bzip2 $SYSROOT_DIR/bin/bunzip2
ln -sv bzip2 $SYSROOT_DIR/bin/bzcat
rm -fv $SYSROOT_DIR/usr/lib/libbz2.a
#shadow
chroot $SYSROOT_DIR "/usr/sbin/pwconv"
chroot $SYSROOT_DIR "/usr/sbin/grpconv"
chroot $SYSROOT_DIR "/usr/bin/passwd root"
#systemd
rm -rf $SYSROOT_DIR/usr/lib/pam.d
chroot $SYSROOT_DIR "systemd-machine-id-setup"
chroot $SYSROOT_DIR "systemctl preset-all"
chroot $SYSROOT_DIR "systemctl disable systemd-time-wait-sync.service"
#dbus
ln -sfv /etc/machine-id $SYSROOT_DIR/var/lib/dbus

step "$totalsteps] Unmount SD card image"
#Mounts the partitions on SD card image
#sudo umount $SYSROOT_DIR/boot
#sudo umount $SYSROOT_DIR
#Unmounts all partitions on image
#sudo kpartx -d $IMAGES_DIR/image.img
