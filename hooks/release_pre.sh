#!/usr/bin/env bash

########################################
########## MAGISK ######################
########################################

# This dirty-as-fuck function is needed to add Magisk into the ramdisk of the BOOT image (which is, in fact, the recovery's ramdisk on system-as-root device)
add_magisk(){
  #https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
  if [ -z ${BUILD_NUMBER+x} ]; then
    BUILD_NUMBER=$(cat ${AOSP_BUILD_DIR}/out/build_number.txt 2>/dev/null)
  fi

  rm -rf ${ROOT_DIR}/workdir

  mkdir -p ${ROOT_DIR}/workdir

  cd ${ROOT_DIR}/workdir

  # Download latest Magisk release
  curl -s https://api.github.com/repos/topjohnwu/Magisk/releases | grep "Magisk-v.*.apk" |grep https|head -n 1| cut -d : -f 2,3|tr -d \" | wget -O magisk-latest.zip -qi -
  
  # Extract the downloaded APK/zip
  unzip -d magisk-latest magisk-latest.zip 

  # Make the fakely-librarized magiskboot executable
  chmod +x ./magisk-latest/lib/x86/libmagiskboot.so

  # Create the needed folder structure
  echo ${AOSP_BUILD_DIR}
  mkdir -p ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/.backup
  mkdir -p ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/overlay.d
  mkdir -p ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/overlay.d/sbin

  # Copy magiskinit to the right location
  rm -f ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/init
  cp magisk-latest/lib/arm64-v8a/libmagiskinit.so ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/init
 
  # Rename libmagisk* to magisk* (main executable daemon) before compressing them
  mv magisk-latest/lib/armeabi-v7a/libmagisk32.so magisk-latest/lib/armeabi-v7a/magisk32
  mv magisk-latest/lib/arm64-v8a/libmagisk64.so magisk-latest/lib/arm64-v8a/magisk64

  # Compress magisk* (main executable daemon)
  ./magisk-latest/lib/x86/libmagiskboot.so compress=xz magisk-latest/lib/armeabi-v7a/magisk32 magisk-latest/lib/armeabi-v7a/magisk32.xz
  ./magisk-latest/lib/x86/libmagiskboot.so compress=xz magisk-latest/lib/arm64-v8a/magisk64 magisk-latest/lib/arm64-v8a/magisk64.xz

  # Copy magisk* (main executable daemon) to the right location
  cp magisk-latest/lib/armeabi-v7a/magisk32.xz ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/overlay.d/sbin/
  cp magisk-latest/lib/arm64-v8a/magisk64.xz ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/overlay.d/sbin/

  # Create Magisk config file. We want to keep dm-verity and encryption.
  cat <<EOF > ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/.backup/.magisk
KEEPFORCEENCRYPT=true
KEEPVERITY=true
RECOVERYMODE=false
EOF

  # Create the .rmlist file that allow to remove/hide the magisk binaries (main executable daemon), once booted
  # The 4 strings (path to files to delete) need to be separated by a null-byte. Maybe there is a more elegant way to do it than using this bash built-in?
  printf '%s\0%s\0%s\0%s\0' overlay.d overlay.d/sbin overlay.d/sbin/magisk32.xz overlay.d/sbin/magisk64.xz > ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/.backup/.rmlist

  # Create a symlink to the real init binary
  rm -f ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/.backup/init
  ln -s /system/bin/init ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/RAMDISK/.backup/init

  # Add our "new" files to the list of files to be packaged/compressed/embedded into the final BOOT image
  if ! grep -q "\.backup" ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files*/META/boot_filesystem_config.txt
  then
     echo "ADDING MAGISK FILES TO THE INCLUDE LIST"
     # I know, this is ugly, but I didn't find a better way to do it yet
     sed -i "/apex 0 0 755 selabel=u:object_r:apex_mnt_dir:s0 capabilities=0x0/a .backup 0 0 000 selabel=u:object_r:rootfs:s0 capabilities=0x0\n.backup/.magisk 0 2000 750 selabel=u:object_r:rootfs:s0 capabilities=0x0\n.backup/.rmlist 0 2000 750 selabel=u:object_r:rootfs:s0 capabilities=0x0\n.backup/init 0 2000 750 selabel=u:object_r:init_exec:s0 capabilities=0x0\noverlay.d 0 0 750 selabel=u:object_r:rootfs:s0 capabilities=0x0\noverlay.d/sbin 0 0 750 selabel=u:object_r:rootfs:s0 capabilities=0x0\noverlay.d/sbin/magisk32.xz 0 0 644 selabel=u:object_r:rootfs:s0 capabilities=0x0\noverlay.d/sbin/magisk64.xz 0 0 644 selabel=u:object_r:rootfs:s0 capabilities=0x0" ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files*/META/boot_filesystem_config.txt
  fi

  # Not needed anymore, but keep it in case of (old devices ?)
  # Retrieve extract-dtb script that will allow us to separate already compiled binary and the concatenated DTB files
  #git clone https://github.com/PabloCastellano/extract-dtb.git
  # Separate kernel and separate DTB files
  #cd extract-dtb
  #python3 ./extract-dtb.py $BUILD_DIR/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/aosp_$DEVICE-target_files-$BUILD_NUMBER/BOOT/kernel

  # Uncompress the kernel
  rm -f ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/uncompressed_kernel
  lz4 -d ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/{kernel,uncompressed_kernel}

  # Hexpatch the kernel ("skip_initramfs" -> "want_initramfs", same length string)
  if grep -Fxq "skip_initramfs" ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/uncompressed_kernel
  then
    ./magisk-latest/lib/x86/libmagiskboot.so hexpatch ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/uncompressed_kernel 736B69705F696E697472616D667300 77616E745F696E697472616D667300
  fi

  # Recompress the kernel
  lz4 -f -9 ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/{uncompressed_kernel,kernel}
  rm ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER/BOOT/uncompressed_kernel

  # Not needed anymore, but keep it in case of (old devices ?)
  # Concatenate back kernel and DTB files
  #rm $BUILD_DIR/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/aosp_$DEVICE-target_files-$BUILD_NUMBER/BOOT/kernel
  #for file in extract-dtb/dtb/*
  #do
  #  cat $file >> $BUILD_DIR/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/aosp_$DEVICE-target_files-$BUILD_NUMBER/BOOT/kernel
  #done

  # Remove target files zip
  rm -f ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER.zip

  # Rezip target files
  cd ${AOSP_BUILD_DIR}/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files-$BUILD_NUMBER
  zip --symlinks -r ../$DEVICE-target_files-$BUILD_NUMBER.zip *
  cd -

}

if [ "${ADD_MAGISK}" == "true" ]; then
    add_magisk
fi