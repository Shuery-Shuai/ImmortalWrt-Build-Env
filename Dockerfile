ARG DEBIAN_TAG=bullseye

FROM debian:$DEBIAN_TAG

# Prepare System Requrements
RUN apt-get update && \
    apt-get install -y \
    sudo bash curl git && \
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
