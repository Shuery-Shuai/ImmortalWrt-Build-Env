# 基础镜像按 digest 固定以保证可复现；升级由 Dependabot 每周一提 PR（见 .github/dependabot.yml）。
# 更换 codename（例如 trixie）属于破坏性变更，走 docs/OPTIMIZATION.md §9 的升级触发器流程。
FROM debian:bookworm@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26

LABEL org.opencontainers.image.base.name="docker.io/library/debian:bookworm" \
      org.opencontainers.image.base.digest="sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26"

# 关闭推荐包安装 + 安装期不写文档/手册/本地化文件；两个 .conf 文件内有量化依据。
# 必须在第一个 apt 操作之前生效，因此放在这里而不是 install 层的末尾。
COPY scripts/apt-no-recommends.conf /etc/apt/apt.conf.d/99immortalwrt-build-env
COPY scripts/dpkg-nodoc.conf /etc/dpkg/dpkg.cfg.d/01immortalwrt-build-env-nodoc

# Prepare System Requirements
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get full-upgrade -y

# 包清单唯一事实源：scripts/packages.txt
# 构建脚本唯一样本：scripts/init_build_environment.sh（vendored，上游 commit 见 scripts/upstream.lock）
COPY scripts/packages.txt scripts/init_build_environment.sh /tmp/

RUN apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' /tmp/packages.txt | xargs) && \
    bash /tmp/init_build_environment.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add User ImmortalWrt
RUN useradd -m immortalwrt -s /bin/bash && \
    echo 'immortalwrt ALL=NOPASSWD: ALL' > /etc/sudoers.d/immortalwrt

# Configure Git Info
RUN git config --system user.name "immortalwrt" && \
    git config --system user.email "immortalwrt@build.env"

VOLUME [ "/home/immortalwrt/workdir" ]

USER immortalwrt
WORKDIR /home/immortalwrt/workdir
