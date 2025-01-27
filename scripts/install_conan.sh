# SPDX-FileCopyrightText: 2024 Howetuft
#
# SPDX-License-Identifier: Apache-2.0

CONAN_PROFILE=$WORKSPACE/conan-profiles/conan-profile-${RUNNER_OS}-${RUNNER_ARCH}

function conan_create_install() {
  name=$(echo "$1" | tr '[:upper:]' '[:lower:]')  # Package name in lowercase
  version=$2

  conan create $WORKSPACE/deps/conan/$name \
    --profile:all=$CONAN_PROFILE \
    --build=missing
  conan install --requires=$name/$version@luxcorewheels/luxcorewheels \
    --profile:all=$CONAN_PROFILE \
    --build=missing \
    -vnotice
}


# Script starts here

set -o pipefail
if [[ $RUNNER_OS == "Linux" ]]; then
  cache_dir=/conan-cache
else
  cache_dir=$WORKSPACE/conan-cache
fi

echo "::group::CIBW_BEFORE_BUILD: pip"
pip install conan
pip install ninja
# TODO Remove
if [[ $PYTHON_MINOR == "8" ]]; then
  pip install "numpy < 2"
else
  pip install "numpy >= 2"
fi
echo "::endgroup::"

if [[ $RUNNER_OS == "Linux" ]]; then
  # ispc
  echo "::group::CIBW_BEFORE_BUILD: ispc"
  source /opt/intel/oneapi/ispc/latest/env/vars.sh
  echo "::endgroup::"
fi

echo "::group::CIBW_BEFORE_BUILD: restore conan cache"
# Restore conan cache (add -vverbose to debug)
conan cache restore $cache_dir/conan-cache-save.tgz
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: opensubdiv"
conan_create_install opensubdiv $OPENSUBDIV_VERSION
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: OIDN"
conan_create_install oidn $OIDN_VERSION
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: Blender types"
conan_create_install blender-types $BLENDER_VERSION
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: OIIO"
# Private OIIO uses fmt as header-only
unset CI  # Otherwise OIIO passes -Werror to compiler (MacOS)!
conan_create_install openimageio $OIIO_VERSION
echo "::endgroup::"

if [[ $RUNNER_OS == "Windows" ]]; then
  DEPLOY_PATH=$(cygpath "C:\\Users\\runneradmin")
else
  DEPLOY_PATH=$WORKSPACE
fi

echo "::group::CIBW_BEFORE_BUILD: LuxCore"
cd $WORKSPACE
conan create $WORKSPACE \
  --profile:all=$CONAN_PROFILE \
  --build=missing

# We use full deployer to get rid of the "strange" paths that Conan uses in
# its cache and that hamper ccache.
conan install $WORKSPACE \
  --profile:all=$CONAN_PROFILE \
  --build=missing \
  --deployer=full_deploy \
  --deployer-folder=$DEPLOY_PATH \
  -vverbose

echo "::endgroup::"

echo "::group::Saving dependencies in ${cache_dir}"
conan cache clean "*"  # Clean non essential files
conan remove -c -vverbose "*/*#!latest"  # Keep only latest version of each package
# Save only dependencies of current target (otherwise cache gets bloated)
conan graph info . \
  --format=json \
  --profile:all=$CONAN_PROFILE \
  > graph.json
conan list --graph=graph.json --format=json --graph-binaries=Cache > list.json
conan cache save -vverbose --file=$cache_dir/conan-cache-save.tgz --list=list.json
echo "::endgroup::"
