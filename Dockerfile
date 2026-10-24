# 基础镜像按 digest 固定以保证可复现；升级由 Dependabot 每周一提 PR（见 .github/dependabot.yml）。
# 更换 codename（例如 trixie）属于破坏性变更，走 docs/OPTIMIZATION.md §9 的升级触发器流程。
FROM debian:bookworm@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26

LABEL org.opencontainers.image.base.name="docker.io/library/debian:bookworm" \
      org.opencontainers.image.base.digest="sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26"

# 关闭推荐包安装 + 安装期不写文档/手册/本地化文件；两个 .conf 文件内有量化依据。
# 必须在第一个 apt 操作之前生效，因此放在这里而不是 install 层的末尾。
COPY build/apt-no-recommends.conf /etc/apt/apt.conf.d/99-rtfw-builder
COPY build/dpkg-nodoc.conf /etc/dpkg/dpkg.cfg.d/01-rtfw-builder-nodoc
# bookworm-backports 源：上游脚本假设它存在（只在中国网络分支写入），否则 LLVM 18 / Node / Go
# 的安装会静默失败——详见 build/apt-backports.list 的说明（CI 实测确认）。
COPY build/apt-backports.list /etc/apt/sources.list.d/bookworm-backports.list

# Prepare System Requirements
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get full-upgrade -y

# 包清单唯一事实源：build/packages.txt
# 构建脚本唯一样本：vendor/init_build_environment.sh（vendored，上游 commit 见 vendor/upstream.lock）
COPY build/packages.txt vendor/init_build_environment.sh /tmp/
COPY vendor/patches/ /tmp/patches/

RUN apt-get install -y $(grep -vE '^[[:space:]]*(#|$)' /tmp/packages.txt | xargs) && \
    for p in /tmp/patches/*.patch; do \
      echo "applying ${p}"; \
      patch --batch --forward /tmp/init_build_environment.sh < "${p}" || exit 1; \
    done && \
    bash /tmp/init_build_environment.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add User Builder
RUN useradd -m builder -s /bin/bash && \
    echo 'builder ALL=NOPASSWD: ALL' > /etc/sudoers.d/builder

# Configure Git Info
RUN git config --system user.name "builder" && \
    git config --system user.email "builder@rtfw"

VOLUME [ "/home/builder/workdir" ]

USER builder
WORKDIR /home/builder/workdir
