#!/usr/bin/env bash
set -eo pipefail

STREAMLINK_PYTHON_ARCH="win32"
STREAMLINK_PYTHON_VERSION="3.13.6"
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
        BUILDNAME="py313-x86_64"
        ;;
    amd64)
        PYTHON_PLATFORM="win_amd64"
        BUILDNAME="py313-x86_64"
        ;;
    *)
        echo "error: unknown architecture [$STREAMLINK_PYTHON_ARCH]"
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
venv_dir="${temp_dir}/venv"
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

if [ -d "${venv_dir}" ]; then
    rm -Rf "${venv_dir}"
fi

"${PYTHON_EXECUTABLE}" -m venv "${venv_dir}"
if [ -f "${venv_dir}/bin/activate" ]; then
    # shellcheck disable=1091
    source "${venv_dir}/bin/activate"
elif [ -f "${venv_dir}/Scripts/activate" ]; then
    # shellcheck disable=1091
    source "${venv_dir}/Scripts/activate"
fi

pip install "yq>=3.0.0"

CONFIG_YML="${temp_dir}/config.yml"

wget -c -O "${CONFIG_YML}" "https://raw.githubusercontent.com/streamlink/windows-builds/master/config.yml"

PIP_ARGS=(
  --isolated
  --disable-pip-version-check
)

REQUIREMENTS_WHEELS_FILE="${temp_dir}/requirements_wheels.txt"
yq -r ".builds[\"${BUILDNAME}\"].dependencies | to_entries[] | \"\(.key)==\(.value)\"" < "${CONFIG_YML}" | awk '{ print $1 }' > "${REQUIREMENTS_WHEELS_FILE}"

${PIP_EXECUTABLE} install \
    "${PIP_ARGS[@]}" \
    --only-binary=:all: \
    --platform="${PYTHON_PLATFORM}" \
    --python-version="${STREAMLINK_PYTHON_VERSION}" \
    --implementation="cp" \
    --no-deps \
    --target="${packages_dir}" \
    --no-compile \
    --requirement="${REQUIREMENTS_WHEELS_FILE}"

cd "${STREAMLINK_REPO_DIR}"

${PIP_EXECUTABLE} install \
    "${PIP_ARGS[@]}" \
    --no-cache-dir \
    --platform="${PYTHON_PLATFORM}" \
    --python-version="${STREAMLINK_PYTHON_VERSION}" \
    --implementation="cp" \
    --no-deps \
    --target="${packages_dir}" \
    --no-compile \
    --upgrade \
    "${STREAMLINK_REPO_DIR}"

cd "${root_dir}"

unzip -o "${temp_dir}/python-${STREAMLINK_PYTHON_VERSION}-embed-${STREAMLINK_PYTHON_ARCH}.zip" -d "${python_dir}"
# include the Windows 10 Universal Runtime
unzip -o "msvcrt_${PYTHON_PLATFORM}.zip" -d "${python_dir}"

cp "${root_dir}/streamlink-script.py" "${bundle_dir}/streamlink-script.py"
cp "${root_dir}/streamlink.bat" "${bundle_dir}/streamlink.bat"
cp "${root_dir}/NOTICE" "${bundle_dir}/NOTICE.txt"

ffmpeg_version=$(curl https://www.gyan.dev/ffmpeg/builds/release-version)
wget -c -P "${ffmpeg_dir}" "https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-${ffmpeg_version}-essentials_build.zip"
unzip -o "${ffmpeg_dir}/ffmpeg-${ffmpeg_version}-essentials_build.zip" -d "${ffmpeg_dir}"
ffmpeg_extracted_dir="${ffmpeg_dir}/ffmpeg-${ffmpeg_version}-essentials_build"

mkdir -p "$bundle_dir/ffmpeg"
cp -r "${ffmpeg_extracted_dir}/bin/ffmpeg.exe" "${bundle_dir}/ffmpeg/"
cp -r "${ffmpeg_extracted_dir}/LICENSE" "${bundle_dir}/ffmpeg/"
cp -r "${ffmpeg_extracted_dir}/README.txt" "${bundle_dir}/ffmpeg/"
wget -c -O "${bundle_dir}/config.default" "https://raw.githubusercontent.com/streamlink/windows-installer/master/files/config"

sed -i "s/^ffmpeg-ffmpeg=.*/#ffmpeg-ffmpeg=/g" "${bundle_dir}/config.default"

cd "${STREAMLINK_REPO_DIR}"

STREAMLINK_VERSION=$(PYTHONPATH="${packages_dir}" python -c "from importlib.metadata import version;print(version('streamlink'))")
STREAMLINK_VERSION=$(echo "${STREAMLINK_VERSION}" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+).*/\1/g')
STREAMLINK_VERSION_EXTENDED="$(git describe --tags | sed 's/v//g')"
build_date=$(date "+%Y%m%d")
STREAMLINK_VERSION_EXTENDED="${STREAMLINK_VERSION_EXTENDED}-$(git rev-parse --abbrev-ref HEAD)"
STREAMLINK_VERSION_EXTENDED="${STREAMLINK_VERSION_EXTENDED}-${build_date}"
STREAMLINK_VERSION="${STREAMLINK_VERSION} (${STREAMLINK_VERSION_EXTENDED})"

rm "${bundle_dir}/packages/streamlink/_version.py"
echo "__version__ = \"${STREAMLINK_VERSION}\"" > "${bundle_dir}/packages/streamlink/_version.py"

cd "${temp_dir}"

if [[ "${USE_SEVEN_ZIP}" == "true" ]]; then
    7z a -r -mx9 -ms=on -mmt -xr!__pycache__/ "${dist_dir}/streamlink-portable-${STREAMLINK_VERSION_EXTENDED}-py${STREAMLINK_PYTHON_VERSION}-${STREAMLINK_PYTHON_ARCH}.7z" "streamlink"
else
    zip --exclude "*/__pycache__/*" -r "${dist_dir}/streamlink-portable-${STREAMLINK_VERSION_EXTENDED}-py${STREAMLINK_PYTHON_VERSION}-${STREAMLINK_PYTHON_ARCH}.zip" "streamlink"
fi

cd "${root_dir}"
