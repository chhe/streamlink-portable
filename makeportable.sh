#!/usr/bin/env bash
# This script takes one argument, the windows arch for which to build it (win32 or amd64) and it defaults to win32
set -e # quit on error

STREAMLINK_PYTHON_ARCH="win32"
STREAMLINK_PYTHON_VERSION="3.5.2"
PYTHON_EXECUTABLE="env python"
PIP_EXECUTABLE="pip"
USE_SEVEN_ZIP="false"
DO_CLEAN="false"

while getopts ":a:s:p:c7i:" option; do
    case $option in
        a)
            STREAMLINK_PYTHON_ARCH=$OPTARG
            ;;
        s)
            STREAMLINK_REPO_DIR=$OPTARG
            ;;
        p)
            PYTHON_EXECUTABLE=$OPTARG
            ;;
        i)
            PIP_EXECUTABLE=$OPTARG
            ;;
        c)
            DO_CLEAN="true"
            ;;
        7)
            USE_SEVEN_ZIP="true"
            ;;
        \?)
            echo "error: unknown option -$OPTARG"
            exit 1
            ;;
        :)
            echo "option -$OPTARG requires an argument"
            exit 1
            ;;
    esac
done

case $STREAMLINK_PYTHON_ARCH in
    win32)
        PYTHON_PLATFORM="win32"
        ;;
    amd64)
        PYTHON_PLATFORM="win_amd64"
        ;;
    *)
        echo "error: unknow architecture [$STREAMLINK_PYTHON_ARCH]"
        exit 1
        ;;
esac

python_url="https://www.python.org/ftp/python/${STREAMLINK_PYTHON_VERSION}/python-${STREAMLINK_PYTHON_VERSION}-embed-${STREAMLINK_PYTHON_ARCH}.zip"

root_dir="$(pwd)"
temp_dir="${root_dir}/build/temp"
bundle_dir="${temp_dir}/streamlink"
python_dir="${bundle_dir}/python"
packages_dir="${bundle_dir}/packages"
streamlink_clone_dir="${temp_dir}/streamlink-clone"
dist_dir="${root_dir}/dist"

if [[ "$DO_CLEAN" == "true" ]]; then
    rm -Rf ${root_dir}/build
fi

mkdir -p "${bundle_dir}"
mkdir -p "${dist_dir}"

wget "${python_url}" -c -O "build/temp/python-${STREAMLINK_PYTHON_VERSION}-embed-${STREAMLINK_PYTHON_ARCH}.zip"

if [[ -z ${STREAMLINK_REPO_DIR} ]]; then
    # remove any old streamlink clone
    rm -rf "${streamlink_clone_dir}"
    git clone https://github.com/streamlink/streamlink.git ${streamlink_clone_dir}

    STREAMLINK_REPO_DIR=${streamlink_clone_dir}
fi

pushd "${STREAMLINK_REPO_DIR}"
git checkout .

${PIP_EXECUTABLE} download --only-binary ":all:" --platform "${PYTHON_PLATFORM}" --python-version "35" --abi "cp35m" -d "${temp_dir}" "pycryptodome==3.4.3" "requests>=1.0,!=2.12.0,!=2.12.1,<3.0"
${PIP_EXECUTABLE} install -t "${packages_dir}" "iso-639" "iso3166" "setuptools" "six" "appdirs" "packaging" "pyparsing" "urllib3" "idna" "chardet" "certifi"

STREAMLINK_VERSION=$(python setup.py --version)
STREAMLINK_VERSION_EXTENDED="$(git describe --tags | sed 's/v//g')"
sdate=$(date "+%Y%m%d")
STREAMLINK_VERSION_EXTENDED="${STREAMLINK_VERSION_EXTENDED}-$(git rev-parse --abbrev-ref HEAD)"
STREAMLINK_VERSION_EXTENDED="${STREAMLINK_VERSION_EXTENDED}-${sdate}"
STREAMLINK_VERSION="${STREAMLINK_VERSION} (${STREAMLINK_VERSION_EXTENDED})"

env NO_DEPS=1 $PYTHON_EXECUTABLE "setup.py" sdist -d "${temp_dir}"

popd

unzip -o "build/temp/python-${STREAMLINK_PYTHON_VERSION}-embed-${STREAMLINK_PYTHON_ARCH}.zip" -d "${python_dir}"
# include the Windows 10 Universal Runtime
unzip -o "msvcrt_${PYTHON_PLATFORM}.zip" -d "${python_dir}"

unzip -o "build/temp/pycryptodome*.whl" -d "${packages_dir}"
unzip -o "build/temp/requests*.whl" -d "${packages_dir}"

cp -r "${STREAMLINK_REPO_DIR}/src/"* "${bundle_dir}/packages"
cp "${root_dir}/streamlink-script.py" "${bundle_dir}/streamlink-script.py"
cp "${root_dir}/streamlink.bat" "${bundle_dir}/streamlink.bat"
cp "${root_dir}/NOTICE" "${bundle_dir}/NOTICE.txt"

mkdir -p "$bundle_dir/rtmpdump" "$bundle_dir/ffmpeg"
cp -r "${STREAMLINK_REPO_DIR}/win32/rtmpdump/"* "${bundle_dir}/rtmpdump"
cp -r "${STREAMLINK_REPO_DIR}/win32/ffmpeg/"* "${bundle_dir}/ffmpeg"
cp -r "${STREAMLINK_REPO_DIR}/win32/streamlinkrc" "${bundle_dir}/streamlinkrc.default"
cp -r "${STREAMLINK_REPO_DIR}/win32/LICENSE.txt" "${bundle_dir}/LICENSE.txt"

sed -i "s/^rtmpdump=.*/#rtmpdump=/g" "${bundle_dir}/streamlinkrc.default"
sed -i "s/^ffmpeg-ffmpeg=.*/#ffmpeg-ffmpeg=/g" "${bundle_dir}/streamlinkrc.default"

sed -i "/__version__ =/c\__version__ = \"${STREAMLINK_VERSION}\"" "${bundle_dir}/packages/streamlink/__init__.py"

pushd "${temp_dir}"

if [[ "${USE_SEVEN_ZIP}" == "true" ]]; then
    7z a -r -mx9 -ms=on -mmt -xr!__pycache__/ "${dist_dir}/streamlink-portable-${STREAMLINK_VERSION_EXTENDED}-py${STREAMLINK_PYTHON_VERSION}-${STREAMLINK_PYTHON_ARCH}.7z" "streamlink"
else
    zip --exclude "*/__pycache__/*" -r "${dist_dir}/streamlink-portable-${STREAMLINK_VERSION_EXTENDED}-py${STREAMLINK_PYTHON_VERSION}-${STREAMLINK_PYTHON_ARCH}.zip" "streamlink"
fi

popd
