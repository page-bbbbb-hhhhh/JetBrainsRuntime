#!/bin/bash -x

# The following parameters must be specified:
#   JBSDK_VERSION    - specifies the current version of OpenJDK e.g. 11_0_6
#   JDK_BUILD_NUMBER - specifies the number of OpenJDK build or the value of --with-version-build argument to configure
#   build_number     - specifies the number of JetBrainsRuntime build
#   bundle_type      - specifies bundle to bu built; possible values:
#                        jcef - the bundles with jcef
#                        empty - the bundles without jcef
#
# jbrsdk-${JBSDK_VERSION}-osx-x64-b${build_number}.tar.gz
# jbr-${JBSDK_VERSION}-osx-x64-b${build_number}.tar.gz
#
# $ ./java --version
# openjdk 11.0.6 2020-01-14
# OpenJDK Runtime Environment (build 11.0.6+${JDK_BUILD_NUMBER}-b${build_number})
# OpenJDK 64-Bit Server VM (build 11.0.6+${JDK_BUILD_NUMBER}-b${build_number}, mixed mode)
#

JBSDK_VERSION=$1
JDK_BUILD_NUMBER=$2
build_number=$3
bundle_type=$4
JBSDK_VERSION_WITH_DOTS=$(echo $JBSDK_VERSION | sed 's/_/\./g')

source jb/project/tools/common.sh

function create_jbr {

  if [ -z "${bundle_type}" ]; then
    JBR_BUNDLE=jbr
  else
    JBR_BUNDLE=jbr_${bundle_type}
  fi
  rm -rf ${JBR_BUNDLE}

  echo Running jlink....
  ${JSDK}/bin/jlink \
    --module-path ${JSDK}/jmods --no-man-pages --compress=2 \
    --add-modules $(xargs < modules_tmp.list | sed s/" "//g) --output ${JBR_BUNDLE} || exit $?

  [ ! -z "${bundle_type}" ] && (cp -R jcef_win_x64/* ${JBR_BUNDLE}/bin || exit $?)
  echo Modifying release info ...
  cat ${JSDK}/release | tr -d '\r' | grep -v 'JAVA_VERSION' | grep -v 'MODULES' >> ${JBR_BUNDLE}/release
}

JBRSDK_BASE_NAME=jbrsdk-${JBSDK_VERSION}
WORK_DIR=$(pwd)

git checkout -- modules.list
git checkout -- src/java.desktop/share/classes/module-info.java
[ -z "$bundle_type" ] && git apply -p0 < jb/project/tools/exclude_jcef_module.patch

PATH="/usr/local/bin:/usr/bin:${PATH}"
sh ./configure \
  --disable-warnings-as-errors \
  --with-native-debug-symbols=none \
  --with-target-bits=64 \
  --with-vendor-name="${VENDOR_NAME}" \
  --with-vendor-version-string="${VENDOR_VERSION_STRING}" \
  --with-version-pre= \
  --with-version-build=${JDK_BUILD_NUMBER} \
  --with-version-opt=b${build_number} \
  --with-import-modules=${WORK_DIR}/modular-sdk \
  --with-toolchain-version=2015 \
  --with-boot-jdk=${BOOT_JDK} \
  --disable-ccache \
  --enable-cds=yes || exit 1

make LOG=info images CONF=windows-x86_64-server-release test-image || exit 1

JSDK=build/windows-x86_64-server-release/images/jdk
JBSDK=${JBRSDK_BASE_NAME}-windows-x64-b${build_number}
BASE_DIR=build/windows-x86_64-server-release/images
JBRSDK_BUNDLE=jbrsdk

rm -rf ${BASE_DIR}/${JBRSDK_BUNDLE} && rsync -a --exclude demo --exclude sample ${JSDK}/ ${JBRSDK_BUNDLE} || exit 1
cp -R jcef_win_x64/* ${JBRSDK_BUNDLE}/bin
sed 's/JBR/JBRSDK/g' ${JSDK}/release > release
mv release ${JBRSDK_BUNDLE}/release

create_jbr || exit $?