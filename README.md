# RtfwBuilder — Router Firmware Builder

[![Docker Publish](https://github.com/Shuery-Shuai/rtfw-builder/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Shuery-Shuai/rtfw-builder/actions)
[![GitHub Container Registry](https://img.shields.io/badge/Container%20Registry-GHCR-black)](https://github.com/Shuery-Shuai/rtfw-builder/pkgs/container/rtfw-builder)
[![Docker Hub](https://img.shields.io/badge/Container%20Registry-DockerHub-blue)](https://hub.docker.com/r/shuery/rtfw-builder)

## 📖 项目简介

**RtfwBuilder**（Router Firmware Builder）用于构建路由器固件编译的 Docker 环境。

本仓库**只提供编译环境**，不包含也不负责固件编译本身。

## 🔀 分支与兼容性

| 分支       | 基础镜像        | 适用宿主系统         | 说明                                                                   |
| ---------- | --------------- | -------------------- | ---------------------------------------------------------------------- |
| `main`     | Debian Bookworm | 见下方「兼容性契约」 | 默认分支，持续更新，**推荐使用**                                       |
| `bullseye` | Debian Bullseye | —                    | **已 EOL 的存档分支**：Debian 11 LTS 已于 2026-08-31 结束，不再有安全更新 |

### 兼容性契约

- **平台**：仅提供 `linux/amd64`（上游构建脚本对非 x86_64 宿主有硬检查，arm64 不可用）。
- **规则**：**镜像的 glibc 版本 ≤ 宿主 glibc 版本**。Debian 只是当前实现，不是契约本身。
- **机制**：容器自带 libc，**宿主 glibc 不参与容器内进程运行**，双方只共享内核。因此
  "宿主 glibc 版本不匹配导致编译失败"是一个常见误解——它通常不是真实原因。
- **旧宿主上真正可能出问题的是宿主运行时**：glibc 2.34+ 依赖 `clone3` 系统调用，宿主 Docker /
  libseccomp 过旧会拦截它，宿主内核过旧同理。**正确做法是升级宿主 Docker（及 libseccomp）或内核。**
- `bullseye` 镜像仅作为无法升级宿主时的**临时回退**，且因上游已 EOL 不再获得安全更新，
  不建议新用户使用。

## 🏷️ 镜像 tag 与引用语义

| tag                         | 类型   | 含义                                                                    |
| --------------------------- | ------ | ----------------------------------------------------------------------- |
| `latest`、`bookworm`        | 浮动   | 指向 `main` 最近一次成功发布；内容会随发布移动                          |
| `bookworm-YYYY.MM.DD[.n]`   | 不可变 | 一次发布的固定快照，**同 tag 永不重写**；同日第二次发布追加 `.1`、`.2`  |
| `bullseye`、`bullseye-v1.0` | 历史   | bullseye 存档线，已冻结，不再更新                                       |

- **需要完全可复现时请用 digest 引用**（`@sha256:…`），tag 只供人类阅读：

  ```sh
  docker pull ghcr.io/shuery-shuai/rtfw-builder@sha256:<digest>
  # 查当前 digest：
  docker buildx imagetools inspect ghcr.io/shuery-shuai/rtfw-builder:bookworm
  ```

- **校验签名**（镜像由 CI 以 keyless 方式签名）：

  ```sh
  cosign verify ghcr.io/shuery-shuai/rtfw-builder@sha256:<digest> \
    --certificate-identity-regexp 'https://github.com/Shuery-Shuai/rtfw-builder/.github/workflows/.*' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

## 🧭 操作指南

### 💽 获取镜像

> [!NOTE]
>
> 可拉取预构建镜像，也可自行构建。

#### 拉取镜像

```bash
# 推荐：浮动 tag（跟随最新发布）
docker pull shuery/rtfw-builder:latest --platform linux/amd64

# 或使用不可变 tag（示例，实际请用 docker buildx imagetools inspect 查询当前可用 tag）
docker pull shuery/rtfw-builder:bookworm-2026.10.04 --platform linux/amd64
```

#### 构建镜像

1. 克隆代码

   ```sh
   git clone --depth 1 https://github.com/Shuery-Shuai/rtfw-builder.git
   ```

2. 进入目录并构建镜像

   ```sh
   cd rtfw-builder
   ```

   - **Linux / Windows**

     ```sh
     docker build --platform linux/amd64 \
       -t shuery/rtfw-builder:latest \
       .
     ```

   - **macOS**

     ```sh
     docker buildx build --platform linux/amd64 \
       -t shuery/rtfw-builder:latest \
       .
     ```

### 📦 运行容器

> [!CAUTION]
>
> 请将 `/path/to/firmware` 替换为你的固件源码（ImmortalWrt / OpenWrt 等）所在路径，该路径需大小写敏感。

```sh
FW_PATH=/path/to/firmware
```

> [!TIP]
>
> 固件源码（ImmortalWrt、OpenWrt 及其各类 fork）的存储路径需要**大小写敏感**，否则编译过程中会出现错误。
>
> 1. 首先需要创建一个大小写敏感的文件夹，用于存储固件源码：
>
>    - **macOS**
>
>      可以先使用 `hdiutil` 创建并挂载 `SparseBundle` 类型的 `Case-sensitive` 磁盘镜像：
>
>      ```sh
>      hdiutil create \
>        -size 64G \
>        -type SPARSEBUNDLE \
>        -fs "Case-sensitive APFS" \
>        -volname Firmware \
>        Firmware.sparsebundle
>      sudo hdiutil attach \
>        -mountpoint $FW_PATH \
>        Firmware.sparsebundle
>      ```
>
>    - **Windows**
>
>      可以先使用 `mkdir` 创建一个**空**文件夹并使用 `fsutil` 设定该文件夹 `CaseSensitive`：
>
>      ```sh
>      mkdir $FW_PATH
>      fsutil file setCaseSensitiveInfo \
>        $FW_PATH enable
>      ```
>
> 2. 然后再克隆固件源码（下例以 ImmortalWrt 为例）：
>
>    ```sh
>    cd $FW_PATH
>    git clone --depth 1 \
>      -b $BRANCH --single-branch \
>      --filter=blob:none \
>      https://github.com/immortalwrt/immortalwrt \
>      .
>    ```

```sh
docker run \
  -itd \
  --name rtfw-builder \
  --platform linux/amd64 \
  -v $FW_PATH:/home/builder/workdir \
  shuery/rtfw-builder:latest
```

### 🚪 进入容器

```sh
docker exec -it rtfw-builder /bin/bash
cd ~/workdir
```

> [!IMPORTANT]
>
> **2026-10-24 改名与迁移**：本项目原为 `ImmortalWrt-Build-Env`，现为 **RtfwBuilder**（仓库路径 `rtfw-builder`）。
>
> - 镜像名随仓库变更：GHCR 新包 `ghcr.io/shuery-shuai/rtfw-builder`，Docker Hub 新仓库 `shuery/rtfw-builder`。
>   旧包 `shuery-shuai/immortalwrt-build-env` 的**已发布 tag 保持可拉取但不再更新**（tag 永不重写）。
> - 容器内用户与工作目录变更：`immortalwrt` → `builder`，`/home/immortalwrt/workdir` → `/home/builder/workdir`。
>   沿用旧挂载路径的自有 CI / 脚本需同步修改。
> - `git clone` 旧仓库地址目前会 301 跳转到新地址，但仍建议更新为 `rtfw-builder`。

## 📦 镜像内容

- **基底**：Debian Bookworm，`FROM` 按 digest 固定；升级由 Dependabot 每周一提 PR。
- **包清单唯一事实源**：[`build/packages.txt`](build/packages.txt)。apt 的 Recommends 已全局关闭
  （体积考虑），经审计判定为承重的推荐包在该文件中显式列出。
- **上游构建脚本**：`init_build_environment.sh` 以 vendored 方式随仓库固定，上游 commit 记录在
  [`vendor/upstream.lock`](vendor/upstream.lock)；同步流程见 [`vendor/README.md`](vendor/README.md)。
- **主要工具**：GCC 12（`gcc`/`g++`/`cc`/`c++` 软链指向它）、LLVM/Clang 18、Python 3、Node.js + yarn、
  Go、ccache、make、rsync、patch、qemu-img、upx、padjffs2、po2lmo、git、gh 等。
- **上游宿主前置条件**：镜像满足 `immortalwrt/prereq-build.mk` 的要求（GCC ≥ 10、Python ≥ 3.8、
  GNU 版 tar/find/bash/xargs/patch/diff、rsync），并由 CI 的冒烟测试持续断言。

## 🤖 在自有 CI 中使用

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/shuery-shuai/rtfw-builder@sha256:<digest> # 建议用 digest 固定
    steps:
      - uses: actions/checkout@v7
      - run: |
          cd $GITHUB_WORKSPACE
          make defconfig
          make -j"$(nproc)"
```

> [!TIP]
>
> 用 `@sha256:…` 引用可以得到完全可复现的编译环境；用浮动 tag 则会跟随上游安全更新，
> 两者取舍见上文「镜像 tag 与引用语义」。

## 📌 补充说明

- **升级建议**：Debian Bullseye 已 EOL，请升级宿主系统后使用 `main` 分支。
- **问题反馈**：如遇兼容性问题，请在 [Issues](https://github.com/Shuery-Shuai/rtfw-builder/issues) 中提出，并注明宿主系统版本与 `docker version` 输出。
