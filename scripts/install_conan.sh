# SPDX-FileCopyrightText: 2024 Howetuft
#
# SPDX-License-Identifier: Apache-2.0

function conan_create_install() {
  name=$(echo "$1" | tr '[:upper:]' '[:lower:]')  # Package name in lowercase
  version=$2

  conan create $WORKSPACE/deps/conan/$name \
    --profile:all=$WORKSPACE/conan_profiles/conan_profile_${RUNNER_OS}_${RUNNER_ARCH} \
    --build=missing \
    -s build_type=Release
  conan install --requires=$name/$version@luxcorewheels/luxcorewheels \
    --profile:all=$WORKSPACE/conan_profiles/conan_profile_${RUNNER_OS}_${RUNNER_ARCH} \
    --build=missing \
    -vverbose \
    -s build_type=Release
}


# Script starts here

set -o pipefail
if [[ $RUNNER_OS == "Linux" ]]; then
  cache_dir=/conan_cache
else
  cache_dir=$WORKSPACE/conan_cache
fi

echo "::group::CIBW_BEFORE_BUILD: pip"
pip install conan
pip install ninja
if [[ $PYTHON_MINOR == "8" ]]; then
  pip install "numpy < 2"
else
  pip install "numpy >= 2"
fi
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: restore conan cache"
# Restore conan cache (add -vverbose to debug)
conan cache restore $cache_dir/conan_cache_save.tgz
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: Boost Python"
# Private boost-python is patched to be compatible with numpy 2
conan_create_install boost-python $BOOST_VERSION
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: OIIO"
# Private OIIO uses fmt as header-only
unset CI  # Otherwise OIIO passes -Werror to compiler (MacOS)!
conan_create_install openimageio $OIIO_VERSION
echo "::endgroup::"

echo "::group::CIBW_BEFORE_BUILD: OIDN"
conan_create_install oidn $OIDN_VERSION
echo "::endgroup::"

if [[ $RUNNER_OS == "Windows" ]]; then
  DEPLOY_PATH=$(cygpath "C:\\Users\\runneradmin")
else
  DEPLOY_PATH=$WORKSPACE
fi

echo "::group::CIBW_BEFORE_BUILD: LuxCore"
conan remove -c "luxcorewheels/*"  # TODO
cd $WORKSPACE
conan create $WORKSPACE \
  --profile:all=$WORKSPACE/conan_profiles/conan_profile_${RUNNER_OS}_${RUNNER_ARCH} \
  --build=missing \
  -s build_type=Release

# We use full deployer to get rid of the "strange" paths that Conan uses in
# its cache and that hamper ccache.
conan install $WORKSPACE \
  --profile:all=$WORKSPACE/conan_profiles/conan_profile_${RUNNER_OS}_${RUNNER_ARCH} \
  --build=missing \
  --deployer=full_deploy \
  --deployer-folder=$DEPLOY_PATH \
  -vverbose \
  -s build_type=Release

echo "::endgroup::"

echo "::group::Saving dependencies in ${cache_dir}"
conan cache clean "*"  # Clean non essential files
conan remove -c -vverbose "*/*#!latest"  # Keep only latest version of each package
conan graph info . \
  --format=json \
  --profile:all=$WORKSPACE/conan_profiles/conan_profile_${RUNNER_OS}_${RUNNER_ARCH} \
  -s build_type=Release \
  > graph.json
conan list --graph=graph.json --format=json --graph-binaries=Cache > list.json
conan cache save -vverbose --file=$cache_dir/conan_cache_save.tgz --list=list.json
echo "::endgroup::"
