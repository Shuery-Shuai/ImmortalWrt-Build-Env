# Changelog

本项目的所有重要变更都记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
版本标识使用日期式不可变 tag `bookworm-YYYY.MM.DD[.n]`（语义见 README 的「镜像 tag 与引用语义」）。

## [未发布]

### 新增

- CI 证据设施：PR 上执行冒烟测试、包清单守门（对比上一版已发布镜像）与体积报告，
  并把报告作为 PR 评论发布、同时上传为 artifact。
- 每月 1 日 04:00 UTC 的从零构建巡检（canary）：`no-cache` 构建 + 冒烟 + 上游脚本漂移检测
  + trivy CVE 扫描（CRITICAL/HIGH，仅报告、不阻断）；每月发布一条**滚动 Issue** 记录结果，
  不推送、不建 tag。
- 发布时生成 SBOM attestation；cosign 升级到 v3 并新增"签名后立即 verify"的校验步骤。
- Dependabot：`docker` 与 `github-actions` 两个生态，每周一提 PR。
- `docs/OPTIMIZATION.md`：优化共识、验收清单与残余缺口。
- 冒烟测试覆盖上游宿主前置条件（`immortalwrt/prereq-build.mk @ 0a9fcdf`：GCC ≥ 10、
  Python ≥ 3.8、GNU 工具集、rsync）与真实编译运行验证。

### 修复

- **已发布镜像缺少 LLVM 18 / Node / Go**：上游脚本在非中国网络下不写入 bookworm-backports 源，
  却用 `-t bookworm-backports` 执行 `apt update` 与安装，失败又被脚本的"无 `set -e`"吞掉。
  现已显式提供该源，镜像补回 clang-18 / nodejs 22 / golang-1.25 / python3-requests 等 51 个包。
- **`llvm-18-dev` 位置错误**：它只存在于 apt.llvm.org（脚本运行中才配置），写在 `scripts/packages.txt`
  会导致构建期 apt exit 100；改由 `scripts/patches/0002-add-llvm-dev.patch` 在脚本的 LLVM 安装行补回。
- **包清单守门的基线镜像名大小写错误**：GHCR 要求全小写，此前一直静默跳过，现已真正执行。
- 移除与上游脚本重复的 Debian LLVM/Clang 14 全套（冒烟确认 clang/lld 仍可用且为 18）。

### 变更

- 基础镜像改为**按 digest 固定**（不再使用浮动的 `debian:bookworm`）。
- 上游构建脚本改为 **vendored**（`scripts/init_build_environment.sh` + `scripts/upstream.lock`），
  不再在构建期 `curl | bash` 拉取远端脚本。
- 包清单抽出为唯一事实源 `scripts/packages.txt`；apt 关闭 Recommends/Suggests，
  并在安装期用 dpkg `path-exclude` 剔除 doc/man/info/locale（保留 copyright 与 C/en* locale）。
- 第三方 GitHub Actions 全部改为**按 commit SHA 固定**，由 Dependabot 维护升级。
- 发布流程改为 CalVer：不可变 tag `bookworm-YYYY.MM.DD[.n]`，浮动别名 `latest`、`bookworm`。
- 项目定位从"ImmortalWrt 专用"泛化为**路由器固件通用编译环境**（ImmortalWrt / OpenWrt 及各类 fork）：
  README 与镜像 OCI `description` 同步措辞，宿主目录变量 `IMMORTALWRT_PATH` 改名为中性的 `FW_PATH`。
- 更正兼容性说明：容器自带 libc，宿主 glibc 不参与容器内进程；旧宿主的问题来自
  Docker/libseccomp 或内核过旧，bullseye 镜像仅为临时回退。
- **目录重组：`scripts/` 按消费方拆为 `build/` + `vendor/` + `ci/`，`scripts/` 目录彻底消失**。
  旧结构把 12 个职能完全不同的文件堆在一层（apt/dpkg 配置片段、包清单、vendored 上游脚本、
  CI 校验脚本混在一起），分类依据是**谁消费这个文件**，不是文件类型：
  `build/` = Dockerfile 直接 `COPY` 进镜像的构建输入（三个 apt/dpkg 片段 + `packages.txt`）；
  `vendor/` = vendored 上游脚本本体 + `upstream.lock` 版本锁 + `patches/`（脚本仍与上游逐字一致，
  `SHA256` 未变，补丁仍由 Dockerfile 以显式文件参数应用）；
  `ci/` = `package-diff.sh` / `smoke-test.sh` 及其读取的 `packages-removed.allow`。
  原 `scripts/README.md` 拆为三份各自成文的 README，每份开头写明本目录的归类判据。
  同时新增 CI 结构守门 job `structure`（跑在 `build` 之前，只查路径不建镜像）：断言旧 `scripts`
  目录下不再有任何文件、仓库根无游离顶层项、三个新目录之下只有已登记文件，失败信息自带归类判据。
  镜像内容与运行时行为不变（`COPY` 目标路径未变）。
  **历史文档与历史条目中的 `scripts/` 路径为当时状态，不再有效**——`docs/verification-2026-10-04.md`
  与本文件上方旧条目按用户要求原样保留、不做改写，以免篡改已验证记录。

### 破坏性变更

- **仓库与镜像改名**：`ImmortalWrt-Build-Env` → `RtfwBuilder` → **`rtfw-builder`**（2026-10-24）。
  GHCR 包名跟随 `github.repository`（自动转小写），新镜像发布于 `ghcr.io/shuery-shuai/rtfw-builder`；
  Docker Hub 侧对应 `shuery/rtfw-builder`（Hub 不支持改名，需新建目标仓库）。
  旧包 `shuery-shuai/immortalwrt-build-env` 的已发布 tag 永不重写、保持可拉取，但不再更新。
- **容器内用户与工作目录变更**：`immortalwrt` / `/home/immortalwrt/workdir` →
  `builder` / `/home/builder/workdir`；挂载需改为 `-v $FW_PATH:/home/builder/workdir`，
  引用旧路径的自有 CI 与脚本要同步修改。冒烟测试的三条用户契约断言已随之更新。
- 双注册表发布、cosign 签名机制与已发布 tag 语义均未变。

## [bullseye-v1.0] - 2026-06-22

- 基于 Debian 11 (Bullseye) 的存档版本。Debian 11 LTS 已于 **2026-08-31** 结束，
  该线与对应镜像不再更新，仅供无法升级宿主的用户临时回退。
