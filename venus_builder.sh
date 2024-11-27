#!/bin/bash -e
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="meson ninja patchelf unzip curl pip flex bison zip"
workdir="$(pwd)/workdir"
magiskdir="$workdir/venus_module"
ndkver="android-ndk-r27c"
sdkver="34"
mesasrc="https://codeload.github.com/android-generic/external_mesa/zip/refs/heads/24.3_prebuilt-intel-shaders"
clear

# there are 4 functions here, simply comment to disable.
# you can insert your own function and make a pull request.
run_all(){
	check_deps
	prepare_workdir
	build_lib_for_android
	port_lib_for_magisk
}


check_deps(){
	echo "Checking system for required Dependencies ..."
	for deps_chk in $deps;
		do
			sleep 0.25
			if command -v "$deps_chk" >/dev/null 2>&1 ; then
				echo -e "$green - $deps_chk found $nocolor"
			else
				echo -e "$red - $deps_chk not found, can't countinue. $nocolor"
				deps_missing=1
			fi;
		done

		if [ "$deps_missing" == "1" ]
			then echo "Please install missing dependencies" && exit 1
		fi

	echo "Installing python Mako dependency (if missing) ..." $'\n'
	pip install mako 
}



prepare_workdir(){
	echo "Creating and entering to work directory ..." $'\n'
	mkdir -p "$workdir" && cd "$_"

	echo "Downloading android-ndk from google server (~640 MB) ..." $'\n'
	curl https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
	###
	echo "Exracting android-ndk to a folder ..." $'\n'
	unzip "$ndkver"-linux.zip  &> /dev/null

	echo "Downloading mesa source (~50 MB) ..." $'\n'
	curl "$mesasrc" --output mesa-24.3.zip &> /dev/null
	###
	echo "Exracting mesa source to a folder ..." $'\n'
	unzip mesa-24.3.zip &> /dev/null
 	mv external_mesa-24.3_prebuilt-intel-shaders mesa-24.3
	cd mesa-24.3
}



build_lib_for_android(){
	echo "Creating meson cross file ..." $'\n'
	ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"

	cat <<EOF >"android-x86_64"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/x86_64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/x86_64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ndk/x86_64-linux-android-strip'
pkg-config = ['/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

	echo "Generating build files ..." $'\n'
	meson setup build-android-x86_64 \
 		--cross-file "$workdir"/mesa-24.3/android-x86_64 \
   -Dbuildtype=release -Dplatforms=android \
   -Dplatform-sdk-version=$sdkver \
   -Dandroid-stub=true \
   -Dgallium-drivers= \
   -Dvulkan-drivers=virtio \
   -Dvulkan-beta=true \
   -Db_lto=true \
   -Dstrip=true \
   -Dcpp_rtti=false \
   -Dvideo-codecs= \
   -Dzstd=disabled \
   -Dexpat=disabled 

	echo "Compiling build files ..." $'\n'
	ninja -C build-android-x86_64
}



port_lib_for_magisk(){
	echo "Using patchelf to match soname ..."  $'\n'
	cp "$workdir"/mesa-24.3/build-android-x86_64/src/virtio/vulkan/libvulkan_virtio.so "$workdir"
	cd "$workdir"
	patchelf --set-soname vulkan.virtio.so libvulkan_virtio.so
	mv libvulkan_virtio.so vulkan.virtio.so

	if ! [ -a vulkan.virtio.so ]; then
		echo -e "$red Build failed! $nocolor" && exit 1
	fi

	echo "Prepare magisk module structure ..." $'\n'
	p1="system/vendor/lib64/hw"
	mkdir -p "$magiskdir" && cd "$_"
	mkdir -p "$p1"

	meta="META-INF/com/google/android"
	mkdir -p "$meta"

	cat <<EOF >"$meta/update-binary"
#################
# Initialization
#################
umask 022
ui_print() { echo "\$1"; }
OUTFD=\$2
ZIPFILE=\$3
. /data/adb/magisk/util_functions.sh
install_module
exit 0
EOF

	cat <<EOF >"$meta/updater-script"
#MAGISK
EOF

	cat <<EOF >"module.prop"
id=turnip
name=turnip
version=$(cat $workdir/mesa-24.3/VERSION)
versionCode=1
author=MrMiy4mo
description=Turnip is an open-source vulkan driver for devices with adreno GPUs.
EOF

	cat <<EOF >"customize.sh"
set_perm_recursive \$MODPATH/system 0 0 755 u:object_r:system_file:s0
set_perm_recursive \$MODPATH/system/vendor 0 2000 755 u:object_r:vendor_file:s0
set_perm \$MODPATH/$p1/vulkan.virtio.so 0 0 0644 u:object_r:same_process_hal_file:s0
EOF

	echo "Copy necessary files from work directory ..." $'\n'
	cp "$workdir"/vulkan.virtio.so "$magiskdir"/"$p1"

	echo "Packing files in to magisk module ..." $'\n'
	zip -r "$workdir"/vulkan-virtio.zip ./* &> /dev/null
	if ! [ -a "$workdir"/vulkan-virtio.zip ];
		then echo -e "$red-Packing failed!$nocolor" && exit 1
		else echo -e "$green-All done, you can take your module from here;$nocolor" && echo "$workdir"/vulkan-virtio.zip
	fi
}

run_all
