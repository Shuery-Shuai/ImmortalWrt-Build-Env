ARG DEBIAN_TAG=bullseye

FROM debian:$DEBIAN_TAG

# Prepare System Requrements
RUN apt-get update && \
    apt-get install -y \
    sudo bash curl git \
    ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
    bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
    g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
    libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
    libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm lrzsz mkisofs msmtp nano \
    ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
    python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs \
    upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd && \
    bash -c \
    'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)' && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add User ImmortalWrt
RUN useradd -m immortalwrt -s /bin/bash && \
    echo 'immortalwrt ALL=NOPASSWD: ALL' > /etc/sudoers.d/immortalwrt

# Configure Git Info
RUN git config --system user.name "immortalwrt" && \
    git config --system user.email "immortalwrt@example.com"

VOLUME [ "/home/immortalwrt" ]

USER immortalwrt
WORKDIR /home/immortalwrt
