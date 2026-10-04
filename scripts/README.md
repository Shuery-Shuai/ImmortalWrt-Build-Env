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

## 已知残余缺口

上游脚本内部仍有两处构建期未固定引用（`padjffs2.c` 取自 `openwrt/openwrt` 的 `main` 分支、
`po2lmo` 来自 `openwrt/luci.git` 默认分支的 `git clone`），会让"同一 commit 构建出不同镜像"。
修复方式为**单独维护 patch**（保持本文件与上游逐字一致，差异全部集中在 patch 中），见
`docs/OPTIMIZATION.md` §10。
