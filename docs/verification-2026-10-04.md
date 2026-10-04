# 一次性验证记录（2026-10-04）

## 方法

在正式 PR 之前，用**临时**的一次性验证通道（位于临时分支 `verify/scratch` 的 `verify-only.yml`，
由 `smokeverify*` tag 触发，验证完成后即删除）
在 GitHub runner 上执行**真实的无缓存构建 + 镜像内冒烟 + 包清单守门 + 体积测量**。
该通道**不推送任何镜像、不签名、不建 Release**，产物回写到 `verify/scratch` 分支供匿名读取。

## 结果（第六次运行）

| 项目 | 结果 |
| ---- | ---- |
| 从零构建（no-cache） | ✅ 成功 |
| 镜像内冒烟 | ✅ 56 项断言全过 |
| 包清单守门（对比已发布镜像） | ✅ 386 项移除、**0 项未登记** |
| 体积 | 2.7 GB 未压缩 / **822 MB 分层 gzip 合计（注册表口径）** —— 验收标准 ≤ 1000 MB **已达成** |
| 上游漂移检测 | ✅ 锁定 commit 与上游 master 一致（该步骤为 canary 的组成，已单独验证） |
| CVE 扫描（trivy） | ✅ 步骤可用：620 项 HIGH/CRITICAL（588 HIGH / 32 CRITICAL），按共识**只报告不阻断** |
| cosign v3 签名 / 验签 | ✅ 端到端通过（本地注册表）：keyless 签名 + 与 README/workflow 相同的验签参数均成功 |

> 体积口径说明：`docker save` 导出后逐层 gzip(6) 求和，与注册表存储方式一致；本次测得 822 MB，
> 与整包 gzip 估算（822 MB）相同。已发布镜像同口径为 1506 MB（851 个包）。

## 由此发现并修复的缺陷

1. **`llvm-18-dev` 写进 `packages.txt` 必然构建失败**：它只存在于 apt.llvm.org，而该源由上游脚本
   在运行中才配置，此时尚未就位 → apt 以 exit 100 失败。改由
   `scripts/patches/0002-add-llvm-dev.patch` 在脚本的 LLVM 安装行补回。
2. **已发布镜像缺少 LLVM 18 / Node / Go**：上游脚本在「非中国网络」分支不写入 bookworm-backports 源，
   却用 `-t bookworm-backports` 执行 `apt update` 与安装；`apt update` 的失败让刚配置好的第三方源
   （apt.llvm.org / nodesource / yarn / golang PPA）列表从未刷新，而脚本没有 `set -e`，失败被静默吞掉。
   修复：显式提供该源（`scripts/apt-backports.list`）。修复后镜像新增 51 个包，
   含 `clang-18`、`nodejs 22`、`golang-1.25`、`python3-requests`、`quilt`、`jq` 等。
3. **包清单守门的基线名大小写错误**：GHCR 要求仓库路径全小写，`ghcr.io/Shuery-Shuai/...` 拉取失败，
   导致守门自加入以来从未真正执行过。修复：在步骤内 `tr` 成小写（fork 同样适用）。
4. **冗余的 LLVM/Clang 14 全套**：镜像里同时存在 Debian 自带的 14 与上游脚本安装的 18，
   而脚本已把 `/usr/lib/llvm-18/bin/*` 软链进 `/usr/bin`。移除 14 全套后冒烟确认
   `clang`/`clang++`/`lld` 仍可用且版本为 18，体积随之下降。

## 尚未验证的部分（需真实发布）

- buildx 的 SBOM attestation 生成（`sbom: true`）——只有推送到真实注册表时才会产生。
- CalVer 不可变 tag 的创建、GitHub Release 生成、PR 评论发布。
- 注册表实际存储的压缩体积（本地测得的分层 gzip 合计 822 MB 已是同口径代理）。

## 残留

- 体积验收以**注册表分层压缩合计**为准（822 MB 目前只是整包 gzip 估算），需在首次发布后核对。
- 上游脚本内部的失败静默问题（无 `set -e`）未被修改：vendored 文件保持与上游逐字一致，
  由冒烟断言兜底（这正是本次能发现第 2 条缺陷的原因）。
