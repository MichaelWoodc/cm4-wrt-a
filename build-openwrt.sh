#!/bin/bash
#
# Build OpenWrt image for the the CM4-WRT-A baseboard. It also builds a service 
# named picod, which is a tool for monitoring the Raspberry Pi Pico on the 
# CM4-WRT-A baseboard: 
# https://www.tindie.com/products/mytechcatalog/rpi-cm4-router-baseboard-with-nvme/
################################################################################

openwrt_git="https://git.openwrt.org/openwrt/openwrt.git"
github_git="https://github.com/openwrt/openwrt.git"

# Try to get latest tag from OpenWrt Git
branch=$(git ls-remote --tags ${openwrt_git} 'refs/tags/v*' 2>/dev/null | \
grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | cut -d/ -f3 | sort -V | tail -n 1)

# If OpenWrt Git fails, fallback to GitHub
if [ -z "$branch" ]; then
  echo -e "\033[1;33mOpenWrt Git unreachable, falling back to GitHub...\033[0m"
  git_url="${github_git}"
  branch=$(git ls-remote --tags ${git_url} 'refs/tags/v*' 2>/dev/null | \
  grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | cut -d/ -f3 | sort -V | tail -n 1)
else
  git_url="${openwrt_git}"
fi

[ -z "$branch" ] && branch="master"
echo -e "Using OpenWrt: \033[1;36m${branch}\033[0m"

CONTAINER_NAME=openwrt-build
imageName="openwrt:${branch}"
scripDir=$(dirname "$0") 
basePath=$(realpath "${scripDir}")
dockerFile=${basePath}/OpenWrtDockerfile

[ ! -d "${basePath}/bin" ] && { mkdir "${basePath}/bin"; }

cfgUrl="https://downloads.openwrt.org/releases/${branch#v*}/targets/bcm27xx/bcm2711/config.buildinfo"

theId=$(docker ps -aqf "name=^${CONTAINER_NAME}$")
[ -z ${theId} ] && { printf "#This file is auto-generated.\nFROM debian:bookworm-slim\n\n" > ${dockerFile}; } &&\
{ printf "RUN useradd build -u $(id -u) -m -c 'OpenWrt Builder'\n" >> ${dockerFile}; } &&\
{ printf "RUN apt-get update\n" >> ${dockerFile}; } &&\
{ printf "RUN apt install -y build-essential clang \\" >> ${dockerFile}; } &&\
{ printf "\n\tflex bison g++ gawk gcc-multilib g++-multilib \\" >> ${dockerFile}; } &&\
{ printf "\n\tgettext git libncurses5-dev libssl-dev \\" >> ${dockerFile}; } &&\
{ printf "\n\tpython3-distutils python3-pip rsync unzip zlib1g-dev file wget\n" >> ${dockerFile}; } &&\
{ printf "RUN pip3 install --break-system-packages pyserial\n" >> ${dockerFile}; } &&\
{ printf "USER build\n" >> ${dockerFile}; } &&\
{ printf "RUN mkdir ~/openwrt ~/picod\n" >> ${dockerFile}; } &&\
{ printf "WORKDIR /home/build/openwrt\n" >> ${dockerFile}; } &&\
{ printf "RUN git clone -b ${branch} ${git_url} .\n" >> ${dockerFile}; } &&\
{ printf "RUN make distclean\n" >> ${dockerFile}; } &&\
{ printf "RUN ./scripts/feeds update -a\n" >> ${dockerFile}; } &&\
{ printf "RUN ./scripts/feeds install -a\n" >> ${dockerFile}; } &&\
{ printf "RUN git clone https://github.com/AlvinEmo/patches-for-dahdi-linux.git /home/build/patches-for-dahdi-linux\n" >> ${dockerFile}; } &&\
{ printf "RUN mkdir -p feeds/telephony/libs/dahdi-linux/patches\n" >> ${dockerFile}; } &&\
{ printf "RUN mkdir -p feeds/telephony/dahdi-linux/patches\n" >> ${dockerFile}; } &&\
{ printf "RUN find /home/build/patches-for-dahdi-linux -name '*.patch' -exec cp {} feeds/telephony/libs/dahdi-linux/patches/ \\;\n" >> ${dockerFile}; } &&\
{ printf "RUN find /home/build/patches-for-dahdi-linux -name '*.patch' -exec cp {} feeds/telephony/dahdi-linux/patches/ \\;\n" >> ${dockerFile}; } &&\
{ printf "RUN echo '/home/build/CM4/create_picod_links.sh' > ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ printf "RUN echo 'cp -r /home/build/CM4/package /home/build/openwrt/' >> ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ printf "RUN wget --output-document=/home/build/openwrt/.config ${cfgUrl}\n" >> ${dockerFile}; } &&\
{ printf "RUN echo 'cat /home/build/CM4/diffconfig >> /home/build/openwrt/.config' >> ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ printf "RUN echo 'make defconfig && make tools/install -j\$(nproc) && make toolchain/install -j\$(nproc)' >> ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ printf "RUN echo 'cp /home/build/CM4/config.txt ./target/linux/bcm27xx/image/config.txt' >> ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ printf "RUN echo 'make -j\$(nproc) defconfig download clean world' >> ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ printf "RUN chmod +x ~/build-openwrt.sh\n" >> ${dockerFile}; } &&\
{ docker build ${basePath}/ -f ${dockerFile} -t ${imageName}; } &&\
{ docker run -t -d --name ${CONTAINER_NAME} \
    -v "${basePath}"/CM4/:/home/build/CM4 \
    -v "${basePath}"/pico/:/home/build/pico:ro \
    -v "${basePath}"/bin/:/home/build/openwrt/bin ${imageName}; } &&\
{ docker exec -it ${CONTAINER_NAME} bash -c "/home/build/build-openwrt.sh"; exit 0;}

[ "$( docker container inspect -f '{{.State.Running}}' ${CONTAINER_NAME} )" == "true" ] &&\
{ docker exec -it ${CONTAINER_NAME} bash; exit 0; }

[ "$( docker container inspect -f '{{.State.Running}}' ${CONTAINER_NAME} )" == "false" ] &&\
{ echo -e "Starting \033[1;36m${CONTAINER_NAME}\033[0m" && docker start ${CONTAINER_NAME}; } &&\
{ docker exec -it ${CONTAINER_NAME} bash; exit 0; }

# Later on within the Docker container, you can rebuild the picod package
#make package/picod/{clean,compile} -j$(nproc)

# Change the OpenWrt configuration file
#make menuconfig

# Save the updated configuration file
#./scripts/diffconfig.sh > ~/CM4/diffconfig

# Rebuild the OpenWrt images
#make -j$(nproc) defconfig download clean world
