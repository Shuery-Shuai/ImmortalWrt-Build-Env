# scripts/

## 为什么 vendored

`init_build_environment.sh` 原先由 Dockerfile 在构建期用 `curl | bash` 从
`https://build-scripts.immortalwrt.org/` 直接拉取并以 root 执行。该脚本在上游仓库
（`immortalwrt/build-scripts`）**没有任何 tag**，只能按 commit 固定，且远端行为随时可能变化——
一旦上游改行为或文件 404，本项目的构建会**突然失败且无从复现**。

因此改为随仓库固定（vendored）：
`init_build_environment.sh` 与上游对应 commit **逐字一致**，版本记录在 `upstream.lock`。

## 同步流程（人工）

1. CI 的每月 canary 会比对 `upstream.lock` 的 `COMMIT` 与上游分支 HEAD，发现不一致时开 Issue。
2. 维护者按 Issue 中的链接查看上游 diff，评估影响（新增依赖？镜像源变化？破坏性变更？）。
3. 更新文件与锁：
   ```sh
   COMMIT=<上游新 commit>
   curl -fsSL "https://raw.githubusercontent.com/immortalwrt/build-scripts/$COMMIT/init_build_environment.sh" \
     -o scripts/init_build_environment.sh
   shasum -a 256 scripts/init_build_environment.sh   # 更新 upstream.lock 的 SHA256
   ```
4. 同一 PR 内更新 `upstream.lock` 的 `COMMIT` / `SHA256` / `FETCHED`，并在 CHANGELOG 记一条。

**不做自动同步 PR**：该脚本以 root 身份在构建期执行，自动同步等于把上游任何改动直接送进流水线，
审查疲劳下极易误合。

## 补丁（`patches/`）

`init_build_environment.sh` 与上游**逐字一致**；我们对该脚本的所有改动都以 patch 形式存放于
`scripts/patches/`，由 Dockerfile 在运行前按文件名顺序应用（`patch --batch --forward`，
应用失败即中断构建）。这样上游同步时面对的永远是"干净的原始脚本 + 少量显式补丁"。

| 补丁 | 内容 | 锚点 |
| ---- | ---- | ---- |
| `0001-pin-extra-artifacts.patch` | 钉死脚本内部两处构建期未固定的远端引用：`padjffs2.c` 与 `openwrt/luci.git`（用于构建 `po2lmo`） | `padjffs2.c` 自 2016-07-11（`d06b68f`）未再变动；`luci` 固定为 `aa3d488`（2026-10-01） |
| `0002-add-llvm-dev.patch` | 在脚本的 LLVM 安装行补上 `llvm-$LLVM_VERSION-dev`：关闭 Recommends 后它不再被隐式带入，而它只存在于 apt.llvm.org（脚本运行中才配置），无法写进 `packages.txt` | 脚本第 254 行的 LLVM 安装行 |

这两处 pin **不会自动更新**：需要时人工 bump（改 patch → 更新上表 → CI 冒烟重跑）。
理由：它们是稳定的构建期小工具，"可复现"比"总是最新"更重要。

## 已知残余缺口

暂无。历史上"脚本内部两处未固定引用"的缺口已由上述 patch 闭环（见 `docs/OPTIMIZATION.md` §10）。
