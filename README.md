# ImmortalWrt Build Environment

## 简介

用于构建 ImmortalWrt 固件编译的 Docker 环境。

## 用法

### 获取镜像

> [!NOTE]
>
> 可选直接[拉取镜像](#拉取镜像)，也可以自行[构建镜像](#构建镜像)。

#### 拉取镜像

```bash
docker pull shuery/immortalwrt-build-env:latest
```

#### 构建镜像

1. 克隆本仓库

   ```sh
   git clone --depth 1 https://github.com/Shuery-Shuai/ImmortalWrt-Build-Env.git
   ```

2. 构建镜像

   - Linux/Windows

     ```sh
     docker build -t shuery/immortalwrt-build-env:latest ImmortalWrt-Build-Env
     ```

   - macOS

     ```sh
     docker buildx build --platform linux/amd64 -t shuery/immortalwrt-build-env:latest ImmortalWrt-Build-Env
     ```

### 运行容器

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
>      hdiutil createvolume -size 64G -fs "Case-sensitive APFS" -type SPARSEBUNDLE -name -volname ImmortalWrt
>      hdiutil attach -mountpoint $IMMORTALWRT_PATH ImmortalWrt.sparsebundle
>      ```
>
>    - **Windows**
>
>      可以先使用 `mkdir` 创建一个**空**文件夹并使用 `fsutil` 设定该文件夹 `CaseSensitive`：
>
>      ```sh
>      mkdir $IMMORTALWRT_PATH
>      fsutil file setCaseSensitiveInfo $IMMORTALWRT_PATH enable
>      ```
>
> 2. 然后再克隆 ImmortalWrt 源码：
>
>    ```sh
>    cd $IMMORTALWRT_PATH
>    git clone -b <branch> --single-branch --filter=blob:none https://github.com/immortalwrt/immortalwrt .
>    ```

```sh
docker run \
  -itd \
  --name immortalwrt-build-env \
  -v $IMMORTALWRT_PATH:/home/immortalwrt \
  shuery/immortalwrt-build-env:latest
```

### 进入容器

```sh
docker exec -it immortalwrt-build-env /bin/bash
```
