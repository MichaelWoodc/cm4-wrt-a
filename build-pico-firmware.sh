#!/bin/bash
#
# Build Raspberry Pi Pico firmware for the CM4-WRT-A baseboard: 
# https://www.tindie.com/products/mytechcatalog/rpi-cm4-router-baseboard-with-nvme/
################################################################################

set -e

CONTAINER_NAME=pico-build
imageName="pico-image"

# $0 always points to the shell script name.
scripDir=$(dirname "$0")
basePath=$(realpath "${scripDir}")
dockerFile=${basePath}/PicoDockerfile
picoDir="/home/build/pico"
binDir="${picoDir}/build"
PICO_SDK_PATH="/home/build/pico-sdk"
GITVER="$(git -C ${basePath} describe --long --tags --dirty --always)"

theId=$(docker ps -aqf "name=^${CONTAINER_NAME}$")

# Create Dockerfile if container does not exist
if [ -z "${theId}" ]; then
cat <<EOF > "${dockerFile}"
# Auto-generated Dockerfile for Pico build
FROM debian:stable-slim

RUN useradd build -u $(id -u) -m -c 'RPi Pico Builder' \
 && apt-get update \
 && apt install -y git cmake gcc-arm-none-eabi \
    libnewlib-arm-none-eabi build-essential nano python3-dev

USER build
WORKDIR /home/build
RUN git clone https://github.com/raspberrypi/pico-sdk.git ~/pico-sdk
RUN git -C ~/pico-sdk submodule update --init
EOF
fi

# Build Docker image using Buildx (BuildKit)
docker buildx build --load -f "${dockerFile}" -t ${imageName} "${basePath}"

# Run container
if ! docker container inspect ${CONTAINER_NAME} &>/dev/null; then
    docker run -d --name ${CONTAINER_NAME} \
        -e PICO_SDK_PATH=${PICO_SDK_PATH} \
        -e GITVER=${GITVER} \
        -v "${basePath}/pico":${picoDir} \
        ${imageName}
fi

# Build Pico firmware inside container
docker exec -it -w ${picoDir} ${CONTAINER_NAME} bash -c "mkdir -p ${binDir} && cd ${binDir} && cmake /home/build/pico/ && make"

# Attach to container shell
if [ "$(docker container inspect -f '{{.State.Running}}' ${CONTAINER_NAME})" == "true" ]; then
    echo -e "Attaching to \033[1;36m${CONTAINER_NAME}\033[0m"
    docker exec -e GITVER=${GITVER} -it -w ${picoDir} ${CONTAINER_NAME} bash
else
    echo -e "Starting \033[1;36m${CONTAINER_NAME}\033[0m"
    docker start ${CONTAINER_NAME}
    docker exec -e PICO_SDK_PATH=${PICO_SDK_PATH} -e GITVER=${GITVER} -it -w ${picoDir} ${CONTAINER_NAME} bash
fi
