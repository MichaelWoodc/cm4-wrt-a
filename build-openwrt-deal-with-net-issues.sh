#!/bin/bash
#
# Build OpenWrt image for the CM4-WRT-A baseboard. It also builds a service 
# named picod, which monitors the Raspberry Pi Pico on the CM4-WRT-A baseboard:
# https://www.tindie.com/products/mytechcatalog/rpi-cm4-router-baseboard-with-nvme/
################################################################################

set -e

git_url="https://git.openwrt.org/openwrt/openwrt.git"

# Pick latest release tag unless passed explicitly
if [ -z "$1" ]; then
  branch=$(git ls-remote --tags ${git_url} 'refs/tags/v*' | grep -v '{}' | tail -n 1 | awk '{print $2}' | cut -d'/' -f3)
else
  branch="$1"
fi

echo -e "Using OpenWrt: \033[1;36m${branch}\033[0m"

CONTAINER_NAME=openwrt-build
imageName="openwrt:${branch}"
scriptDir=$(dirname "$0")
basePath=$(realpath "${scriptDir}")
dockerFile="${basePath}/OpenWrtDockerfile"

[ ! -d "${basePath}/bin" ] && mkdir "${basePath}/bin"

cfgUrl="https://downloads.openwrt.org/releases/${branch#v*}/targets/bcm27xx/bcm2711/config.buildinfo"
theId=$(docker ps -aqf "name=^${CONTAINER_NAME}$")

# Generate Dockerfile only if container doesn't exist
if [ -z "${theId}" ]; then
cat <<EOF > "${dockerFile}"
# This file is auto-generated.
FROM debian:bookworm-slim

RUN useradd build -u $(id -u) -m -c 'OpenWrt Builder'

RUN apt-get update && \
    apt-get install -y build-essential clang \
    flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses5-dev libssl-dev \
    python3-distutils rsync unzip zlib1g-dev file wget ca-certificates

USER build
RUN mkdir -p ~/openwrt ~/picod
WORKDIR /home/build/openwrt

# Improve git reliability with larger buffers and retries
RUN git config --global http.postBuffer 1048576000 && \
    git config --global http.lowSpeedLimit 0 && \
    git config --global http.lowSpeedTime 999999 && \
    git config --global core.compression 0

# Force fresh repo clone with retry logic
RUN rm -rf /home/build/openwrt/* && \
    for i in 1 2 3; do \
        git clone --depth 1 -b ${branch} ${git_url} . && break || \
        (echo "Clone attempt \$i failed, retrying..." && sleep 30 && rm -rf ./* .git); \
    done

# Feeds update with retry logic for each feed
RUN make distclean
RUN for feed in packages luci routing; do \
        for i in 1 2 3; do \
            ./scripts/feeds update \$feed && break || \
            (echo "Feed \$feed update attempt \$i failed, retrying..." && sleep 30); \
        done; \
    done

# Feeds install with continue on error
RUN ./scripts/feeds install -a || echo "Some feeds failed to install, continuing..."

# Create build script
RUN echo '/home/build/CM4/create_picod_links.sh' > ~/build-openwrt.sh && \
    echo 'cp -r /home/build/CM4/package /home/build/openwrt/' >> ~/build-openwrt.sh && \
    wget --output-document=/home/build/openwrt/.config ${cfgUrl} && \
    echo 'cat /home/build/CM4/diffconfig >> /home/build/openwrt/.config' >> ~/build-openwrt.sh && \
    echo 'make defconfig && make tools/install -j\$(nproc) && make toolchain/install -j\$(nproc)' >> ~/build-openwrt.sh && \
    echo 'cp /home/build/CM4/config.txt ./target/linux/bcm27xx/image/config.txt' >> ~/build-openwrt.sh && \
    # Disable picod if it fails to build \
    echo 'sed -i "s/CONFIG_PACKAGE_picod=y/# CONFIG_PACKAGE_picod is not set/" .config 2>/dev/null || true' >> ~/build-openwrt.sh && \
    echo 'make -j\$(nproc) defconfig download clean world' >> ~/build-openwrt.sh && \
    chmod +x ~/build-openwrt.sh
EOF
fi

# Build image and run container
docker build "${basePath}" -f "${dockerFile}" -t "${imageName}"
docker run -t -d --name "${CONTAINER_NAME}" \
    -v "${basePath}/CM4:/home/build/CM4" \
    -v "${basePath}/pico:/home/build/pico:ro" \
    -v "${basePath}/bin:/home/build/openwrt/bin" "${imageName}"

docker exec -it "${CONTAINER_NAME}" bash -c "/home/build/build-openwrt.sh" || true

if [ "$(docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME})" == "true" ]; then
  docker exec -it ${CONTAINER_NAME} bash
else
  echo -e "Starting \033[1;36m${CONTAINER_NAME}\033[0m"
  docker start ${CONTAINER_NAME}
  docker exec -it ${CONTAINER_NAME} bash
fi