#!/bin/bash
#
# Build OpenWrt image for the CM4-WRT-A baseboard using Docker Buildx.
################################################################################

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

git_url="https://git.openwrt.org/openwrt/openwrt.git"
[ "x$1" == "x" ] && { branch=v24.10.4; } || { branch="$1"; }

echo -e "Using OpenWrt: \033[1;36m${branch}\033[0m"

CONTAINER_NAME=openwrt-build
imageName="openwrt:${branch}"
scriptDir=$(dirname "$0")
basePath=$(realpath "${scriptDir}")
dockerFile=${basePath}/OpenWrtDockerfile

# Make bin folder if it doesn't exist
[ ! -d "${basePath}/bin" ] && mkdir "${basePath}/bin"

# Dockerfile
cat > ${dockerFile} <<EOF
FROM debian:bookworm-slim

RUN useradd build -u $(id -u) -m -c 'OpenWrt Builder'
RUN apt-get update
RUN apt install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget

USER build
RUN mkdir ~/openwrt ~/picod
WORKDIR /home/build/openwrt
EOF

# Build Docker image with Buildx
docker buildx create --name openwrt-builder --use >/dev/null 2>&1 || true
docker buildx build --load ${basePath}/ -f ${dockerFile} -t ${imageName}

# Run container with mounted host OpenWrt and CM4 folders
docker run -it --name ${CONTAINER_NAME} \
    -v "${HOME}/openwrt":/home/build/openwrt \
    -v "${basePath}/CM4":/home/build/CM4 \
    -v "${basePath}/pico":/home/build/pico:ro \
    -v "${basePath}/bin":/home/build/openwrt/bin \
    ${imageName} bash -c "
# Copy CM4 packages
cp -r /home/build/CM4/package /home/build/openwrt/
wget --output-document=/home/build/openwrt/.config https://downloads.openwrt.org/releases/24.10.4/targets/bcm27xx/b>
cat /home/build/CM4/diffconfig >> /home/build/openwrt/.config

# Prepare build script
echo '/home/build/CM4/create_picod_links.sh' > ~/build-openwrt.sh
echo 'cp -r /home/build/CM4/package /home/build/openwrt/' >> ~/build-openwrt.sh
echo 'cp /home/build/CM4/config.txt ./target/linux/bcm27xx/image/config.txt' >> ~/build-openwrt.sh
echo 'make defconfig && make tools/install -j\$(nproc) && make toolchain/install -j\$(nproc)' >> ~/build-openwrt.sh
echo 'make -j\$(nproc) defconfig download clean world' >> ~/build-openwrt.sh
chmod +x ~/build-openwrt.sh

# Run the build
~/build-openwrt.sh
bash
"


