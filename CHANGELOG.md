# Changelog

本项目的所有重要变更都记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
版本标识使用日期式不可变 tag `bookworm-YYYY.MM.DD[.n]`（语义见 README 的「镜像 tag 与引用语义」）。

## [未发布]

### 新增

- CI 证据设施：PR 上执行冒烟测试、包清单守门（对比上一版已发布镜像）与体积报告，
  并把报告作为 PR 评论发布、同时上传为 artifact。
- 每月 1 日 04:00 UTC 的从零构建巡检（canary）：`no-cache` 构建 + 冒烟 + 上游脚本漂移检测，
  失败或漂移时开/更新 Issue；不推送、不建 tag。
- 发布时生成 SBOM attestation；cosign 升级到 v3 并新增"签名后立即 verify"的校验步骤。
- Dependabot：`docker` 与 `github-actions` 两个生态，每周一提 PR。
- `docs/OPTIMIZATION.md`：优化共识、验收清单与残余缺口。
- 冒烟测试覆盖上游宿主前置条件（`immortalwrt/prereq-build.mk @ 0a9fcdf`：GCC ≥ 10、
  Python ≥ 3.8、GNU 工具集、rsync）与真实编译运行验证。

### 变更

- 基础镜像改为**按 digest 固定**（不再使用浮动的 `debian:bookworm`）。
- 上游构建脚本改为 **vendored**（`scripts/init_build_environment.sh` + `scripts/upstream.lock`），
  不再在构建期 `curl | bash` 拉取远端脚本。
- 包清单抽出为唯一事实源 `scripts/packages.txt`；apt 关闭 Recommends/Suggests，
  并在安装期用 dpkg `path-exclude` 剔除 doc/man/info/locale（保留 copyright 与 C/en* locale）。
- 第三方 GitHub Actions 全部改为**按 commit SHA 固定**，由 Dependabot 维护升级。
- 发布流程改为 CalVer：不可变 tag `bookworm-YYYY.MM.DD[.n]`，浮动别名 `latest`、`bookworm`。
- 更正兼容性说明：容器自带 libc，宿主 glibc 不参与容器内进程；旧宿主的问题来自
  Docker/libseccomp 或内核过旧，bullseye 镜像仅为临时回退。

### 破坏性变更

- 无（镜像名、容器内用户 `immortalwrt`、工作目录 `/home/immortalwrt/workdir`、双注册表
  与 cosign 签名均未变；已发布 tag 语义不变）。

## [bullseye-v1.0] - 2026-06-22

- 基于 Debian 11 (Bullseye) 的存档版本。Debian 11 LTS 已于 **2026-08-31** 结束，
  该线与对应镜像不再更新，仅供无法升级宿主的用户临时回退。
