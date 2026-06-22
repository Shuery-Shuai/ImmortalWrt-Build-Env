# ImmortalWrt Build Environment

[![Docker Publish](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/actions)
[![GitHub Container Registry](https://img.shields.io/badge/Container%20Registry-GHCR-black)](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/pkgs/container/immortalwrt-build-env)
[![Docker Hub](https://img.shields.io/badge/Container%20Registry-DockerHub-blue)](https://hub.docker.com/r/shuery/immortalwrt-build-env)

## 📖 项目简介

用于构建 ImmortalWrt 固件编译的 Docker 环境。

## 🔀 分支与兼容性

| 分支       | 基础镜像        | 适用宿主系统              | 说明                                                          |
| ---------- | --------------- | ------------------------- | ------------------------------------------------------------- |
| `main`     | Debian Bookworm | Debian 12+, Ubuntu 22.04+ | 默认分支，持续更新，**推荐使用**                              |
| `bullseye` | Debian Bullseye | Debian 11 (glibc 2.31)    | 仅维护兼容性，已冻结，建议有条件者升级宿主系统后切换回 `main` |

> [!IMPORTANT]
> 如果你的宿主系统是 **Debian Bullseye (11.x)**，请使用 `bullseye` 分支或对应的容器标签，避免 glibc 版本不匹配导致编译失败。  
> 已基于 `bullseye` 分支发布稳定 Tag `v1.0-bullseye`，可直接下载使用。

## 🧭 操作指南

### 💽 获取镜像

> [!NOTE]
>
> 可拉取预构建镜像，也可自行构建。**请根据宿主系统选择对应的标签**。

#### 拉取镜像

```bash
# 适用于 Debian Bookworm / Ubuntu 22.04+（推荐）
docker pull shuery/immortalwrt-build-env:latest --platform linux/amd64

# 适用于 Debian Bullseye (glibc 2.31)
docker pull shuery/immortalwrt-build-env:bullseye --platform linux/amd64
```

#### 构建镜像

1. 克隆代码（请根据需求选择分支）

   ```sh
   # 默认 main 分支（Bookworm）
   git clone --depth 1 https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env.git

   # 或指定 bullseye 分支
   git clone --depth 1 -b bullseye https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env.git
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

     > 若在 `bullseye` 分支下构建，可将标签改为 `bullseye`。

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
  shuery/immortalwrt-build-env:latest   # Bullseye 用户请用 :bullseye
```

### 🚪 进入容器

```sh
docker exec -it immortalwrt-build-env /bin/bash
cd ~/workdir
```

---

## 📌 补充说明

- **升级建议**：Debian Bullseye 已进入 EOL 阶段，若条件允许请将宿主系统升级至 Bookworm 或 Ubuntu 22.04+，使用 `main` 分支获得最新支持。
- **问题反馈**：如遇兼容性问题，请在 [Issues](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/issues) 中提出，并注明使用的宿主系统版本。
