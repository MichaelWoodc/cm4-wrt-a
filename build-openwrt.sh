#!/bin/bash
#
# Build OpenWrt image for the CM4-WRT-A baseboard using Docker Buildx (BuildKit).
# It also builds a service named picod, which monitors the Raspberry Pi Pico on the CM4-WRT-A baseboard.
# https://www.tindie.com/products/mytechcatalog/rpi-cm4-router-baseboard-with-nvme/
################################################################################

set -e

git_url="https://git.openwrt.org/openwrt/openwrt.git"

# Determine OpenWrt branch/tag
[ "x$1" == "x" ] && branch=$(git ls-remote --tags ${git_url} 'refs/tags/v*' | grep '[^\{\}]$' | tail -n 1 | awk '{print $2}' | cut -d'/' -f3) || branch="$1"
echo -e "Using OpenWrt: \033[1;36m${branch}\033[0m"

CONTAINER_NAME=openwrt-build
imageName="openwrt:${branch}"

# Directories
scripDir=$(dirname "$0")
basePath=$(realpath "${scripDir}")
dockerFile=${basePath}/OpenWrtDockerfile

[ ! -d "${basePath}/bin" ] && mkdir "${basePath}/bin"

cfgUrl="https://downloads.openwrt.org/releases/${branch#v*}/targets/bcm27xx/bcm2711/config.buildinfo"

# Create Dockerfile if not exists
if [ ! -f "${dockerFile}" ]; then
cat <<EOF > "${dockerFile}"
# Auto-generated Dockerfile for OpenWrt Build
FROM debian:bookworm-slim

RUN useradd build -u $(id -u) -m -c 'OpenWrt Builder' \
 && apt-get update \
 && apt install -y build-essential clang \
    flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses5-dev libssl-dev \
    python3-distutils rsync unzip zlib1g-dev file wget

USER build
RUN mkdir ~/openwrt ~/picod
WORKDIR /home/build/openwrt
RUN git clone -b ${branch} ${git_url} .
RUN make distclean
RUN ./scripts/feeds update -a
RUN ./scripts/feeds install -a
RUN echo '/home/build/CM4/create_picod_links.sh' > ~/build-openwrt.sh
RUN echo 'cp -r /home/build/CM4/package /home/build/openwrt/' >> ~/build-openwrt.sh
RUN wget --output-document=/home/build/openwrt/.config ${cfgUrl}
RUN echo 'cat /home/build/CM4/diffconfig >> /home/build/openwrt/.config' >> ~/build-openwrt.sh
RUN echo 'make defconfig && make tools/install -j\$(nproc) && make toolchain/install -j\$(nproc)' >> ~/build-openwrt.sh
RUN echo 'cp /home/build/CM4/config.txt ./target/linux/bcm27xx/image/config.txt' >> ~/build-openwrt.sh
RUN echo 'make -j\$(nproc) defconfig download clean world' >> ~/build-openwrt.sh
RUN chmod +x ~/build-openwrt.sh
EOF
fi

# Build Docker image using Buildx (BuildKit)
docker buildx build --load -t ${imageName} -f ${dockerFile} "${basePath}"

# Run container
if ! docker container inspect ${CONTAINER_NAME} &>/dev/null; then
    docker run -d --name ${CONTAINER_NAME} \
        -v "${basePath}/CM4":/home/build/CM4 \
        -v "${basePath}/pico":/home/build/pico:ro \
        -v "${basePath}/bin":/home/build/openwrt/bin \
        ${imageName}
fi

# Execute build inside container
docker exec -it ${CONTAINER_NAME} bash -c "/home/build/build-openwrt.sh"

# Attach to container shell
if [ "$(docker container inspect -f '{{.State.Running}}' ${CONTAINER_NAME})" == "true" ]; then
    docker exec -it ${CONTAINER_NAME} bash
else
    echo -e "Starting \033[1;36m${CONTAINER_NAME}\033[0m"
    docker start ${CONTAINER_NAME}
    docker exec -it ${CONTAINER_NAME} bash
fi

# Notes:
# To rebuild picod inside the container:
# make package/picod/{clean,compile} -j$(nproc)
# To update OpenWrt configuration:
# make menuconfig
# Save config changes:
# ./scripts/diffconfig.sh > ~/CM4/diffconfig
# Rebuild OpenWrt:
# make -j$(nproc) defconfig download clean world
