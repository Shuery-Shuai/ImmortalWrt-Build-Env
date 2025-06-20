# ImmortalWrt Build Environment

[![Docker Publish](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/actions)
[![GitHub Container Registry](https://img.shields.io/badge/Container%20Registry-GHCR-black)](https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env/pkgs/container/immortalwrt-build-env)
[![Docker Hub](https://img.shields.io/badge/Container%20Registry-DockerHub-blue)](https://hub.docker.com/r/shuery/immortalwrt-build-env)

## 📖 项目简介

用于构建 ImmortalWrt 固件编译的 Docker 环境。

## 🧭 操作指南

### 💽 获取镜像

> [!NOTE]
>
> 可选直接[拉取镜像](#拉取镜像)，也可以自行[构建镜像](#构建镜像)。

#### 拉取镜像

```bash
docker pull shuery/immortalwrt-build-env:latest --platform linux/amd64
```

#### 构建镜像

1. 克隆代码

   ```sh
   git clone --depth 1 https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env.git
   ```

2. 构建镜像

   - Linux/Windows

     ```sh
     docker build --platform linux/amd64 \
       -t shuery/immortalwrt-build-env:latest \
       ImmortalWrt-Build-Env
     ```

   - macOS

     ```sh
     docker buildx build --platform linux/amd64 \
       -t shuery/immortalwrt-build-env:latest \
       ImmortalWrt-Build-Env
     ```

### 📦 运行容器

> [!CAUTION]
>
> 请将 `/path/to/immortalwrt` 替换为你的 ImmortalWrt 源码路径。

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
  -v $IMMORTALWRT_PATH:/home/immortalwrt \
  shuery/immortalwrt-build-env:latest
```

### 🚪 进入容器

```sh
docker exec -it immortalwrt-build-env /bin/bash
```
