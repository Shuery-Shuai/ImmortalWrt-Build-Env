ARG DEBIAN_TAG=bookworm

FROM debian:$DEBIAN_TAG

# Prepare System Requirements
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get full-upgrade -y

RUN apt-get install -y \
    sudo bash \
    ack asciidoc autoconf automake autopoint binutils bison build-essential \
    bzip2 ccache clang cmake cpio curl device-tree-compiler flex gawk gettext gcc-multilib \
    g++-multilib git gperf haveged help2man intltool libc6-dev-i386 libelf-dev \
    libglib2.0-dev libgmp-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
    libreadline-dev libssl-dev libtool libyaml-dev lld llvm lrzsz msmtp nano \
    ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
    python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo \
    unzip vim wget xmlto xxd zlib1g-dev zstd genisoimage \
    libgnutls28-dev && \
    bash -c \
    'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)' && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Fix Complie Link
RUN set -ex && \
    # Search latest GCC version
    LATEST_GCC=$(ls /usr/bin/gcc-* | grep -E 'gcc-[0-9]+$' | sort -V | tail -n1) && \
    if [ -z "$LATEST_GCC" ]; then \
    echo "ERROR: No GCC version found in /usr/bin"; \
    exit 1; \
    fi && \
    # Get version number
    GCC_VERSION=$(basename "$LATEST_GCC" | cut -d'-' -f2) && \
    echo "Detected GCC version: $GCC_VERSION" && \
    # Remove old links
    rm -f /usr/bin/gcc /usr/bin/g++ /usr/bin/cc /usr/bin/c++ \
    /usr/bin/gcc-ar /usr/bin/gcc-nm /usr/bin/gcc-ranlib && \
    # Create new links
    ln -s "$LATEST_GCC" /usr/bin/gcc && \
    ln -s "/usr/bin/g++-$GCC_VERSION" /usr/bin/g++ && \
    ln -s "/usr/bin/gcc-ar-$GCC_VERSION" /usr/bin/gcc-ar && \
    ln -s "/usr/bin/gcc-nm-$GCC_VERSION" /usr/bin/gcc-nm && \
    ln -s "/usr/bin/gcc-ranlib-$GCC_VERSION" /usr/bin/gcc-ranlib && \
    ln -s /usr/bin/gcc /usr/bin/cc && \
    ln -s /usr/bin/g++ /usr/bin/c++

# Add User ImmortalWrt
RUN useradd -m immortalwrt -s /bin/bash && \
    echo 'immortalwrt ALL=NOPASSWD: ALL' > /etc/sudoers.d/immortalwrt

# Configure Git Info
RUN git config --system user.name "immortalwrt" && \
    git config --system user.email "immortalwrt@build.env"

VOLUME [ "/home/immortalwrt/workdir" ]

USER immortalwrt
WORKDIR /home/immortalwrt/workdir
