#!/usr/bin/env bash
set -e # quit on error

STREAMLINK_PYTHON_ARCH="win32"
STREAMLINK_PYTHON_VERSION="3.10.8"
PYTHON_EXECUTABLE="python"
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
ffmpeg_dir="${root_dir}/build/ffmpeg"
bundle_dir="${temp_dir}/streamlink"
python_dir="${bundle_dir}/python"
packages_dir="${bundle_dir}/packages"
streamlink_clone_dir="${temp_dir}/streamlink-clone"
dist_dir="${root_dir}/dist"

if [[ "$DO_CLEAN" == "true" ]]; then
    rm -Rf "${root_dir}/build"
fi

mkdir -p "${bundle_dir}"
mkdir -p "${dist_dir}"
mkdir -p "${ffmpeg_dir}"

wget "${python_url}" -c -O "build/temp/python-${STREAMLINK_PYTHON_VERSION}-embed-${STREAMLINK_PYTHON_ARCH}.zip"

if [[ -z ${STREAMLINK_REPO_DIR} ]]; then
    # remove any old streamlink clone
    rm -rf "${streamlink_clone_dir}"
    git clone https://github.com/streamlink/streamlink.git "${streamlink_clone_dir}"

    STREAMLINK_REPO_DIR=${streamlink_clone_dir}
fi

cd "${STREAMLINK_REPO_DIR}"

git checkout .

${PIP_EXECUTABLE} install --only-binary=:all: --platform "${PYTHON_PLATFORM}" --python-version "${STREAMLINK_PYTHON_VERSION}" --implementation "cp" --target "${packages_dir}" "pycryptodome>=3.4.3,<4.0" "lxml>=4.6.4,<5.0"
${PIP_EXECUTABLE} install -t "${packages_dir}" "pycountry" "setuptools" "requests>=2.26.0,<3.0" "websocket-client>=0.58.0" "PySocks!=1.5.7,>=1.5.6" "isodate"

cd "${STREAMLINK_REPO_DIR}"

STREAMLINK_VERSION=$(${PYTHON_EXECUTABLE} setup.py --version)
STREAMLINK_VERSION=$(echo "${STREAMLINK_VERSION}" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+).*/\1/g')
STREAMLINK_VERSION_EXTENDED="$(git describe --tags | sed 's/v//g')"
build_date=$(date "+%Y%m%d")
STREAMLINK_VERSION_EXTENDED="${STREAMLINK_VERSION_EXTENDED}-$(git rev-parse --abbrev-ref HEAD)"
STREAMLINK_VERSION_EXTENDED="${STREAMLINK_VERSION_EXTENDED}-${build_date}"
STREAMLINK_VERSION="${STREAMLINK_VERSION} (${STREAMLINK_VERSION_EXTENDED})"

"${PYTHON_EXECUTABLE}" "setup.py" sdist -d "${temp_dir}"
"${PYTHON_EXECUTABLE}" "setup.py" bdist_wheel  -d "${temp_dir}"
"${PYTHON_EXECUTABLE}" "setup.py" bdist_wheel --plat-name "${PYTHON_PLATFORM}" -d "${temp_dir}"

cd "${root_dir}"

unzip -o "${temp_dir}/python-${STREAMLINK_PYTHON_VERSION}-embed-${STREAMLINK_PYTHON_ARCH}.zip" -d "${python_dir}"
# include the Windows 10 Universal Runtime
unzip -o "msvcrt_${PYTHON_PLATFORM}.zip" -d "${python_dir}"

unzip -o "${temp_dir}/streamlink*none-any.whl" -d "${packages_dir}"
unzip -o "${temp_dir}/streamlink*${PYTHON_PLATFORM}.whl" -d "${packages_dir}"

cp "${root_dir}/streamlink-script.py" "${bundle_dir}/streamlink-script.py"
cp "${root_dir}/streamlink.bat" "${bundle_dir}/streamlink.bat"
cp "${root_dir}/NOTICE" "${bundle_dir}/NOTICE.txt"

ffmpeg_version=$(curl https://www.gyan.dev/ffmpeg/builds/release-version)
wget -P "${ffmpeg_dir}" https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-${ffmpeg_version}-essentials_build.zip
unzip "${ffmpeg_dir}/ffmpeg-${ffmpeg_version}-essentials_build.zip" -d "${ffmpeg_dir}"
ffmpeg_extracted_dir="${ffmpeg_dir}/ffmpeg-${ffmpeg_version}-essentials_build"

mkdir -p "$bundle_dir/ffmpeg"
cp -r "${ffmpeg_extracted_dir}/bin/ffmpeg.exe" "${bundle_dir}/ffmpeg/"
cp -r "${ffmpeg_extracted_dir}/LICENSE" "${bundle_dir}/ffmpeg/"
cp -r "${ffmpeg_extracted_dir}/README.txt" "${bundle_dir}/ffmpeg/"
wget -O "${bundle_dir}/config.default" "https://raw.githubusercontent.com/streamlink/windows-installer/master/files/config"

sed -i "s/^ffmpeg-ffmpeg=.*/#ffmpeg-ffmpeg=/g" "${bundle_dir}/config.default"

rm "${bundle_dir}/packages/streamlink/_version.py"
echo "__version__ = \"${STREAMLINK_VERSION}\"" > "${bundle_dir}/packages/streamlink/_version.py"

cd "${temp_dir}"

if [[ "${USE_SEVEN_ZIP}" == "true" ]]; then
    7z a -r -mx9 -ms=on -mmt -xr!__pycache__/ "${dist_dir}/streamlink-portable-${STREAMLINK_VERSION_EXTENDED}-py${STREAMLINK_PYTHON_VERSION}-${STREAMLINK_PYTHON_ARCH}.7z" "streamlink"
else
    zip --exclude "*/__pycache__/*" -r "${dist_dir}/streamlink-portable-${STREAMLINK_VERSION_EXTENDED}-py${STREAMLINK_PYTHON_VERSION}-${STREAMLINK_PYTHON_ARCH}.zip" "streamlink"
fi

cd "${root_dir}"
