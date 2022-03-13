#!/usr/bin/env bash

cd "${AOSP_BUILD_DIR}"

#echo "applying microg patches"
#cd "${AOSP_BUILD_DIR}/packages/modules/Permission"
#patch -p1 --no-backup-if-mismatch < "${AOSP_BUILD_DIR}/platform/prebuilts/microg/00001-fake-package-sig.patch"
#cd "${AOSP_BUILD_DIR}/frameworks/base"
#patch -p1 --no-backup-if-mismatch < "${AOSP_BUILD_DIR}/platform/prebuilts/microg/00002-microg-sigspoof.patch"

patch_mkbootfs(){
  cd "${AOSP_BUILD_DIR}/system/core"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0001_allow_dotfiles_in_cpio.patch"
}

patch_recovery(){
  cd "${AOSP_BUILD_DIR}/bootable/recovery/"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0002_recovery_add_mark_successful_option.patch"
}

patch_bitgapps(){
  log_header "${FUNCNAME[0]}"

  rm -rf "${AOSP_BUILD_DIR}/vendor/gapps"
  retry git clone https://github.com/BiTGApps/aosp-build.git "${AOSP_BUILD_DIR}/vendor/gapps"
  cd "${AOSP_BUILD_DIR}/vendor/gapps"
  git lfs pull

  echo -ne "\\nTARGET_ARCH := arm64" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
  echo -ne "\\nTARGET_SDK_VERSION := 31" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
  echo -ne "\\n\$(call inherit-product, vendor/gapps/gapps.mk)" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
}

patch_safetynet(){
 #cd "${AOSP_BUILD_DIR}/system/security/"
 #patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0003_keystore-Block-key-attestation-for-Google-Play-Servi.patch"

  cd "${AOSP_BUILD_DIR}/frameworks/base/"
  rm -rf "${AOSP_BUILD_DIR}/frameworks/base/core/java/com/android/internal/gmscompat/"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0004_bypass-safetynet.patch"

  cd "${AOSP_BUILD_DIR}/system/core/"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0005_init-set-properties-to-make-safetynet-pass.patch"
}

patch_hardened_malloc(){
  rm -rf "${AOSP_BUILD_DIR}/external/hardened_malloc"
  retry git clone --branch 12 https://github.com/GrapheneOS/hardened_malloc.git "${AOSP_BUILD_DIR}/external/hardened_malloc"
  cd "${AOSP_BUILD_DIR}/bionic"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0006_use-hardened-malloc-from-GrapheneOS.patch"
}

# apply custom hosts file
custom_hosts_file="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
echo "applying custom hosts file ${custom_hosts_file}"
retry wget -q -O "${AOSP_BUILD_DIR}/system/core/rootdir/etc/hosts" "${custom_hosts_file}"

if [ "${ADD_MAGISK}" == "true" ]; then
    patch_mkbootfs
fi
patch_recovery

if [ "${ADD_BITGAPPS}" == "true" ]; then
  patch_bitgapps
fi

# Use a cool alternative bootanimation
if [ "${USE_CUSTOM_BOOTANIMATION}" == "true" ]; then
  cp -f "${CUSTOM_DIR}/prebuilt/bootanimation.zip" "${AOSP_BUILD_DIR}/system/media/bootanimation.zip"
  echo -ne "\\nPRODUCT_COPY_FILES += \\\\\nsystem/media/bootanimation.zip:system/media/bootanimation.zip" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
fi

# Patch Keystore to pass SafetyNet
if [ "${SAFETYNET_BYPASS}" == "true" ]; then
  patch_safetynet
fi

# Patch Bionic libc to use hardened_malloc from GrapheneOS (kudos to @thestinger)
if [ "${USE_HARDENED_MALLOC}" == "true" ]; then
  patch_hardened_malloc
fi
