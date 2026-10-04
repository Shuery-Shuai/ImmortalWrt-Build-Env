# ImmortalWrt Build Environment

[![Docker Publish](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/actions)
[![GitHub Container Registry](https://img.shields.io/badge/Container%20Registry-GHCR-black)](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/pkgs/container/immortalwrt-build-env)
[![Docker Hub](https://img.shields.io/badge/Container%20Registry-DockerHub-blue)](https://hub.docker.com/r/shuery/immortalwrt-build-env)

## 📖 项目简介

用于构建 ImmortalWrt 固件编译的 Docker 环境。

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
  docker pull ghcr.io/shuery-shuai/immortalwrt-build-env@sha256:<digest>
  # 查当前 digest：
  docker buildx imagetools inspect ghcr.io/shuery-shuai/immortalwrt-build-env:bookworm
  ```

- **校验签名**（镜像由 CI 以 keyless 方式签名）：

  ```sh
  cosign verify ghcr.io/shuery-shuai/immortalwrt-build-env@sha256:<digest> \
    --certificate-identity-regexp 'https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/.github/workflows/.*' \
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
docker pull shuery/immortalwrt-build-env:latest --platform linux/amd64

# 或使用不可变 tag（示例，实际请用 docker buildx imagetools inspect 查询当前可用 tag）
docker pull shuery/immortalwrt-build-env:bookworm-2026.10.04 --platform linux/amd64
```

#### 构建镜像

1. 克隆代码

   ```sh
   git clone --depth 1 https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env.git
   ```

2. 进入目录并构建镜像

   ```sh
   cd ImmortalWrt-Build-Env
   ```

   - **Linux / Windows**

     ```sh
     docker build --platform linux/amd64 \
       -t shuery/immortalwrt-build-env:latest \
       .
     ```

   - **macOS**

     ```sh
     docker buildx build --platform linux/amd64 \
       -t shuery/immortalwrt-build-env:latest \
       .
     ```

### 📦 运行容器

> [!CAUTION]
>
> 请将 `/path/to/immortalwrt` 替换为你的 ImmortalWrt 源码所在路径，该路径需大小写敏感。

```sh
IMMORTALWRT_PATH=/path/to/immortalwrt
```

> [!TIP]
>
> ImmortalWrt 源码的存储路径需要**大小写敏感**，否则编译过程中会出现错误。
>
> 1. 首先需要创建一个大小写敏感的文件夹，用于存储 ImmortalWrt 源码：
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
>        -volname ImmortalWrt \
>        ImmortalWrt.sparsebundle
>      sudo hdiutil attach \
>        -mountpoint $IMMORTALWRT_PATH \
>        ImmortalWrt.sparsebundle
>      ```
>
>    - **Windows**
>
>      可以先使用 `mkdir` 创建一个**空**文件夹并使用 `fsutil` 设定该文件夹 `CaseSensitive`：
>
>      ```sh
>      mkdir $IMMORTALWRT_PATH
>      fsutil file setCaseSensitiveInfo \
>        $IMMORTALWRT_PATH enable
>      ```
>
> 2. 然后再克隆 ImmortalWrt 源码：
>
>    ```sh
>    cd $IMMORTALWRT_PATH
>    git clone --depth 1 \
>      -b $BRANCH --single-branch \
>      --filter=blob:none \
>      https://github.com/immortalwrt/immortalwrt \
>      .
>    ```

```sh
docker run \
  -itd \
  --name immortalwrt-build-env \
  --platform linux/amd64 \
  -v $IMMORTALWRT_PATH:/home/immortalwrt/workdir \
  shuery/immortalwrt-build-env:latest
```

### 🚪 进入容器

```sh
docker exec -it immortalwrt-build-env /bin/bash
cd ~/workdir
```

## 📦 镜像内容

- **基底**：Debian Bookworm，`FROM` 按 digest 固定；升级由 Dependabot 每周一提 PR。
- **包清单唯一事实源**：[`scripts/packages.txt`](scripts/packages.txt)。apt 的 Recommends 已全局关闭
  （体积考虑），经审计判定为承重的推荐包在该文件中显式列出。
- **上游构建脚本**：`init_build_environment.sh` 以 vendored 方式随仓库固定，上游 commit 记录在
  [`scripts/upstream.lock`](scripts/upstream.lock)；同步流程见 [`scripts/README.md`](scripts/README.md)。
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
      image: ghcr.io/shuery-shuai/immortalwrt-build-env@sha256:<digest> # 建议用 digest 固定
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
- **问题反馈**：如遇兼容性问题，请在 [Issues](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/issues) 中提出，并注明宿主系统版本与 `docker version` 输出。
