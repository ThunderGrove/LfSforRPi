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
export defaulOflag="-Os"

export CFLAGS=$defaulOflag
export CPPFLAGS=$defaulOflag
export CXXFLAGS=$defaulOflag

export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_STRIP_AND_DELETE_DOCS=1

#End of optional parameters
totalsteps=41
count=0

function step(){
	((count=$count+1))
	echo -e "\e[7m\e[1m>>> [$count/$1\e[0m"
}

function extract(){
	case $1 in
		*.tgz) tar -zxf $1 -C $2 ;;
		*.tar.gz) tar -zxf $1 -C $2 ;;
		*.tar.bz2) tar -jxf $1 -C $2 ;;
		*.tar.xz) tar -Jxf $1 -C $2 ;;
	esac
}

step "$totalsteps] Raspberry Pi Linux Kernel"
extract $SOURCES_DIR/raspberrypi-kernel_1.20210303-1.tar.gz $BUILD_DIR
KERNEL=kernel8 make bcm2711_defconfig -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
#make oldconfig ARCH=arm64 CROSS_COMPILE=$CONFIG_TARGET- -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
#make prepare ARCH=arm64 CROSS_COMPILE=$CONFIG_TARGET- -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
#make -j$PARALLEL_JOBS ARCH=arm64 CROSS_COMPILE=$CONFIG_TARGET- Image modules dtbs -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
#make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_MOD_PATH=$SYSROOT_DIR modules_install -C $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1
#Copy the compiled kernel and other ellements needed for boot from arch/arm64/boot to the boot dir on the SD card image
#cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/Image $SYSROOT_DIR/boot/kernel8.img
#cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/dts/broadcom/*.dtb $SYSROOT_DIR/boot/
#mkdir $SYSROOT_DIR/boot/overlays
#cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/dts/overlays/*.dtb* $SYSROOT_DIR/boot/overlays/
#cp $BUILD_DIR/linux-raspberrypi-kernel_1.20210303-1/arch/arm64/boot/dts/overlays/README $SYSROOT_DIR/boot/overlays/

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
mkdir $BUILD_DIR/glibc-2.33/glibc-build
#--disable-werror are needed else warnings make "make" fail.
( cd $BUILD_DIR/glibc-2.33/glibc-build && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/glibc-2.33/configure \
	--prefix=/usr \
	--enable-shared \
	--enable-obsolete-rpc \
	--enable-kernel=5.10 \
	--disable-werror \
	--with-headers=$SYSROOT_DIR/usr/include )
make -j$PARALLEL_JOBS -C $BUILD_DIR/glibc-2.33/glibc-build
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR install -C $BUILD_DIR/glibc-2.33/glibc-build
rm -rf $BUILD_DIR/glibc-2.33

step "$totalsteps] tcl"
extract $SOURCES_DIR/tcl8.6.11-src.tar.gz $BUILD_DIR
mkdir $BUILD_DIR/tcl8.6.11/unix/tcl-build
( cd $BUILD_DIR/tcl8.6.11/unix/tcl-build && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/tcl8.6.11/unix/configure \
	--prefix=/usr \
	--enable-64bit )
make -j$PARALLEL_JOBS -C $BUILD_DIR/tcl8.6.11/unix/tcl-build
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/tcl8.6.11/unix/tcl-build
#Not all needed parts of tcl gets install with the normal make install so make install-private-headers are also used.
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install-private-headers -C $BUILD_DIR/tcl8.6.11/unix/tcl-build
rm -rf $BUILD_DIR/tcl8.6.11

step "$totalsteps] binutils"
extract $SOURCES_DIR/binutils-2.36.1.tar.xz $BUILD_DIR
( cd $BUILD_DIR/binutils-2.36.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/binutils-2.36.1/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/binutils-2.36.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/binutils-2.36.1
rm -rf $BUILD_DIR/binutils-2.36.1

step "$totalsteps] m4"
#The latest stable version of m4 are not updated to be compile-able with the latest versions of GNUlib so latest version on https://git.savannah.gnu.org/cgit/m4.git/snapshot/m4-branch-1.4.tar.gz are needed and contains aproved comits for next update
extract $SOURCES_DIR/m4-branch-1.4.tar.gz $BUILD_DIR
#The bootstrap script ./bootstrap needs to be executed before ./configure else ./configure will fail
#The bootstrap script will try to download translation files but the files have disappeared from translationproject.org so the code between this comment and the next will download the files from the waybackmachine and disable the use of the original download function
( cd $BUILD_DIR/m4-branch-1.4/po && \
	mkdir .reference && \
	cd .reference && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/bg.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/cs.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/da.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/de.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/el.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/eo.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/es.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/fi.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/fr.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/ga.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/gl.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/hr.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/id.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/ja.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/nl.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/pl.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/pt_BR.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/ro.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/ru.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/sr.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/sv.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/vi.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/zh_CN.po && \
	wget https://web.archive.org/web/20190921162930/https://translationproject.org/latest/m4/zh_TW.po )
filename1="$BUILD_DIR/m4-branch-1.4/bootstrap"
search1="test -d \"\$_G_ref_po_dir\" || mkdir \$_G_ref_po_dir || return"
replace1="#test -d \"\$_G_ref_po_dir\" || mkdir \$_G_ref_po_dir || return"
if [[ $search1 != "" && $replace1 != "" ]]; then
	sed -i "s/$search1/$replace1/" $filename1
fi
filename2="$BUILD_DIR/m4-branch-1.4/bootstrap"
search2="func_download_po_files \$_G_ref_po_dir \$_G_domain"
replace2="#func_download_po_files \$_G_ref_po_dir \$_G_domain"
if [[ $search2 != "" && $replace2 != "" ]]; then
	sed -i "s/$search2/$replace2/" $filename2
fi
filename3="$BUILD_DIR/m4-branch-1.4/bootstrap"
search3='&& ls "$_G_ref_po_dir"\/\*.po 2>\/dev\/null'
replace3='ls "$_G_ref_po_dir"\/\*.po 2>\/dev\/null'
if [[ $search3 != "" && $replace3 != "" ]]; then
	sed -i "s/$search3/$replace3/" $filename3
fi
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
#Without --disable-stripping as a flag on configure the make install command will fail
( cd $BUILD_DIR/ncurses-6.2/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/ncurses-6.2/configure \
	--prefix=/usr \
	--disable-stripping )
make -j$PARALLEL_JOBS -C $BUILD_DIR/ncurses-6.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/ncurses-6.2
rm -rf $BUILD_DIR/ncurses-6.2

step "$totalsteps] bash"
extract $SOURCES_DIR/bash-5.1.tar.gz $BUILD_DIR
( cd $BUILD_DIR/bash-5.1/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/bash-5.1/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bash-5.1
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/bash-5.1
rm -rf $BUILD_DIR/bash-5.1

step "$totalsteps] coreutils"
extract $SOURCES_DIR/coreutils-8.32.tar.xz $BUILD_DIR
#When compiling for 64-bit ARM the command SYS_getdents are called SYS_getdents64. The below find-and-replace will fix this.
filename5="$BUILD_DIR/coreutils-8.32/src/ls.c"
search5="SYS_getdents,"
replace5="SYS_getdents64,"
if [[ $search5 != "" && $replace5 != "" ]]; then
	sed -i "s/$search5/$replace5/" $filename5
fi
( cd $BUILD_DIR/coreutils-8.32/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/coreutils-8.32/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/coreutils-8.32
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/coreutils-8.32
rm -rf $BUILD_DIR/coreutils-8.32

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
#When cross compiling file you need to compile the same version that are installed on host system else make fails.
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
( cd $BUILD_DIR/gawk-5.1.0/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/gawk-5.1.0/configure \
	--prefix=/usr \
	--target=$CONFIG_TARGET \
	--host=$CONFIG_TARGET \
	--build=$CONFIG_HOST )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk-5.1.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gawk-5.1.0
rm -rf $BUILD_DIR/gawk-5.1.0

step "$totalsteps] findutils"
extract $SOURCES_DIR/findutils-4.8.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/findutils-4.8.0/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/findutils-4.8.0/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/findutils-4.8.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/findutils-4.8.0
rm -rf $BUILD_DIR/findutils-4.8.0

step "$totalsteps] grep-3.6"
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
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/sed-4.8
rm -rf $BUILD_DIR/sed-4.8

step "$totalsteps] tar"
extract $SOURCES_DIR/tar-1.34.tar.xz $BUILD_DIR
( cd $BUILD_DIR/tar-1.34/ && \
	CFLAGS="$defaulOflag " CPPFLAGS="" CXXFLAGS="$defaulOflag " LDFLAGS="" \
	$BUILD_DIR/tar-1.34/configure \
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/tar-1.34
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/tar-1.34
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
	--prefix=/usr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gettext-0.21
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/gettext-0.21
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
rm -rf $BUILD_DIR/texinfo-6.7

step "$totalsteps] util-linux"
#extract $SOURCES_DIR/util-linux-2.36.2.tar.xz $BUILD_DIR
#( cd $BUILD_DIR/util-linux-2.36.2/ && \
#	./autogen.sh && \
#	CFLAGS="-Os" CPPFLAGS="" CXXFLAGS="-Os" LDFLAGS="-L$SYSROOT_DIR/usr/lib/ --static" \
#	$BUILD_DIR/util-linux-2.36.2/configure \
#	ADJTIME_PATH=/var/lib/hwclock/adjtime \
#	--docdir=$SYSROOT_DIR/usr/share/doc/util-linux-2.36.2 \
#	--disable-chfn-chsh \
#	--disable-login \
#	--disable-nologin \
#	--disable-su \
#	--disable-setpriv \
#	--disable-runuser \
#	--disable-pylibmount \
#	--disable-static \
#	--without-python \
#	runstatedir=/run )
#The flag --static is need to get make install work when compiling util-linux
#make -j$PARALLEL_JOBS LDFLAGS="-L$SYSROOT_DIR/usr/lib/ --static" -C $BUILD_DIR/util-linux-2.36.2
#make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/util-linux-2.36.2
#rm -rf $BUILD_DIR/util-linux-2.36.2

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
cp -v $BUILD_DIR/bzip2-1.0.8/bzip2-shared $SYSROOT_DIR/bin/bzip2
cp -av $BUILD_DIR/bzip2-1.0.8/libbz2.so* $SYSROOT_DIR/lib
#ln -sv ../../lib/libbz2.so.1.0 $SYSROOT_DIR/usr/lib/libbz2.so
#rm -v $SYSROOT_DIR/usr/bin/{bunzip2,bzcat,bzip2}
#ln -sv bzip2 $SYSROOT_DIR/bin/bunzip2
#ln -sv bzip2 $SYSROOT_DIR/bin/bzcat
#rm -fv $SYSROOT_DIR/usr/lib/libbz2.a
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
	--with-tcl=$SYSROOT_DIR/usr/lib \
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
#make -j$PARALLEL_JOBS -C $BUILD_DIR/dejagnu-1.6.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/dejagnu-1.6.2
#( cd $BUILD_DIR/dejagnu-1.6.2/ && install -v -dm755 $SYSROOT_DIR/usr/share/doc/dejagnu-1.6.2 && install -v -m644 doc/dejagnu.{html,txt} $SYSROOT_DIR/usr/share/doc/dejagnu-1.6.2 )
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

