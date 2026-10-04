# 优化共识（OPTIMIZATION）

> 本文是 2026-10-04 需求澄清会话的结论锚点。**先确认本文，再逐条实施**；实施中若与本文冲突，以本文为准，或先修改本文并说明理由。
> 状态：**已确认（2026-10-04）**。实施进度：① 可复现性地基 ✅ → ③a CI 证据设施 ✅ → ② 体积（实施中，见 §6）→ ③b canary / cosign v3 / SBOM / 发布 → ④ 文档 → ⑤ 首发

## 1. 目标与非目标

### 目标（按优先级）

| 代号 | 目标                                                                 | 验收指标                                                        |
| ---- | -------------------------------------------------------------------- | --------------------------------------------------------------- |
| (b)  | 可复现性：同一 commit 任意时间可从零构建出内容一致的镜像             | 外部输入（base digest、apt 源、脚本）的每次变化都由 PR 显式引入 |
| (a)  | 镜像体积                                                             | 压缩体积 ≤ **1000 MB**（当前 1506 MB，单层 1431 MB）            |
| (e)  | 工程卫生：冒烟测试、依赖自动更新、定时 canary、SBOM、文档纠错        | 见第 7、8 节                                                    |
| (d)  | 定位：成为**外部流水线可消费的稳定基座**（不可变引用 + 文档 + 签名） | 见第 4、8 节                                                    |

### 非目标（明确不做）

- **不在本项目内编译固件**。本仓库只提供编译环境镜像，固件编译在用户侧/其它仓库进行。
- **不做 arm64**。上游 `init_build_environment.sh` 有 `[ "$(uname -m)" == "x86_64" ]` 硬检查，非 x86_64 直接退出；OpenWrt 构建系统的 host 工具链对 arm64 宿主支持有限。将来上游放开再议。
- **本轮不升级 codename**。判据是"能否支持最新 immortalwrt / openwrt 编译"：上游 `prereq-build.mk` 要求 host **GCC ≥ 10**、**Python ≥ 3.8** 及 GNU 版 tar/find/bash/xargs/patch/diff，当前 bookworm + gcc-12 满足，故不动。
- **不做变体镜像 / 可选组件开关**（如 `INSTALL_NODE=0`）。收益不明而 CI、文档、tag 成本翻倍。
- **不新增** SECURITY.md / Issue 模板 / CONTRIBUTING.md。

## 2. 硬约束（用户可见契约，不可变更）

- 镜像名：`ghcr.io/shuery-shuai/immortalwrt-build-env`、`shuery/immortalwrt-build-env`
- 双注册表发布 + cosign 签名
- 容器内用户 `immortalwrt`、工作目录 `/home/immortalwrt/workdir`（README 的 `docker run -v` 直接依赖）
- 已发布 tag 永不重写

## 3. 兼容性契约

- 平台：`linux/amd64`。
- 规则：**镜像 glibc ≤ 宿主 glibc 且 amd64**。Debian 只是当前实现，不是契约本身。
- 机制说明（用于纠正 README 现有说法）：**容器自带 libc，宿主的 glibc 不参与容器内进程运行，双方只共享内核**；macOS / Windows 的 Docker Desktop 里更不存在"宿主 glibc"。因此 README 中"宿主 glibc 版本不匹配导致编译失败"属于错误归因，应删除；旧宿主上真实可能出问题的是宿主 Docker / libseccomp 过旧（glibc 2.34+ 依赖 `clone3`）或内核过旧，对应的正确建议是**升级宿主运行时**。
- `bullseye` 分支与 `bullseye-v1.0`：**保留不删**（不可变），但 README 需标注 Debian 11 LTS 已于 **2026-08-31 EOL**、仅作旧宿主回退方案，不再作为主推路径。

## 4. 版本与 tag（CalVer）

采用日期版本，因为本项目的变更几乎全部由上游漂移驱动，不存在"补丁/功能"语义；SemVer 会逼出一个解决不存在问题的版本状态机。

- **不可变 tag**：`bookworm-YYYY.MM.DD`；同一天第二次及以后发布追加序号 `bookworm-2026.10.05.1`、`.2`。
- **浮动别名**：`latest`、`bookworm`。
- **发布触发**：影响镜像内容的合并到 `main` 后自动发布（CI 打当天日期 tag + 建 Release）；"上游源有更新但仓库无变更"的场景由 `workflow_dispatch` 手动发布，产出的 tag 形状相同。
- **破坏性变更信号**：codename 前缀变更（glibc / 发行版）+ CHANGELOG `### 破坏性变更` 小节 + Release 说明。不使用 `-vX.Y.Z` 语义版本。
- **外部引用**：文档推荐 `@sha256:` digest 引用，tag 仅供人类阅读。
- **CHANGELOG.md**：Keep a Changelog 格式，由 PR 手工维护；发布时自动创建 GitHub Release（含 digest、体积、`cosign verify` 命令）。
- 遗留 `bullseye-v1.0` 保持原样，文档注明为历史风格。
- 实现要点：现有 workflow 的 `DISTRO="${TAG_NAME%-v*}"` 需改为"取第一个 `-` 之前的部分"以派生浮动别名。

## 5. 可复现性

- **Vendor 上游脚本**：把 `init_build_environment.sh` 收入仓库（`scripts/`），并在旁记录上游 `immortalwrt/build-scripts` 的 commit SHA。
  **同步流程：人工**——每月 canary 发现上游新 commit 后开 Issue 提示，由维护者 diff、提交、更新记录的 SHA。不做自动同步 PR（该脚本以 root 身份在构建期执行，自动同步 = 把上游改动直接送进流水线且易被误合）。
- **base image 按 digest 固定**：`FROM debian:bookworm@sha256:…`；Dependabot（`docker` 生态）每周一提更新 PR；镜像 OCI label 记录 base digest 便于对账。
- **CI 依赖固定**：所有第三方 action 改为**完整 commit SHA 固定**（行尾注释保留可读版本）；Dependabot（`github-actions`）每周一提 PR。
- **cosign 升级至 v3.x**（当前 workflow 钉的是 v2.4.3，最新为 v3.1.3），以 CI 内签名 + `cosign verify` 双端验证通过为准；若 v3 有破坏性变更导致验证失败，暂留 v2.4.3 并在本文档记 issue。
- **唯一事实源**：包清单合并到 vendored 脚本/清单，Dockerfile 只负责调用，消除当前 Dockerfile 与上游脚本两份清单重叠的问题。

## 6. 体积优化与守门规则

- 手段：`--no-install-recommends`；清理 `/usr/share/doc`、`/usr/share/man`、`/usr/share/locale`（保留 C 与 en）、apt 缓存与 lists、examples；必要时再评估剥离静态库/头文件（须有证据）。
- **禁止**凭经验删除：`llvm`/`clang`、`node`、静态库、头文件。
- **守门机制（已实装）**：`scripts/package-diff.sh` 在 PR 上以「上一版已发布镜像」为 baseline 比较 `dpkg-query` 包清单，差异写入 Step Summary 并上传 artifact；任何被移除的包必须登记在 `scripts/packages-removed.allow`（附理由，支持 shell 通配模式），否则 CI 失败阻断合并。
- 规则：**先证明再删**。
- **Recommends 处置（已量化）**：以本镜像包集合为种子，Debian bookworm 的 Depends 闭包为 484 包 / 2.2 GB，Depends + Recommends 闭包为 1042 包 / 4.8 GB——**仅 Recommends 就引入 558 包 / 2.6 GB**。因此全局关闭 `APT::Install-Recommends`（`scripts/apt-no-recommends.conf`），并把经审计判定为承重的推荐包显式加回 `scripts/packages.txt`（当前：`llvm-18-dev`、`qemu-block-extra`）。
- **文档与本地化**：用 `dpkg` 的 `path-exclude` 在安装期就不写入 `/usr/share/doc`、`man`、`groff`、`info`、`locale`（保留版权文件与 C/en* locale），而不是装完再删——省的是真实层体积（`scripts/dpkg-nodoc.conf`）。
- **首次以本改动跑 CI 预期会失败**：守门机制要求被移除的包逐个登记，第一次运行会用真实 diff 清单告诉我们到底少了什么，登记后才允许合并。这是设计行为（先证明再删），不是故障。
- 测量口径：以 CI（GitHub runner）的构建时长与注册表压缩体积为准（本机 Apple Silicon 构建走模拟，不具代表性）。

## 7. CI 骨架

| Job            | 触发                       | 行为                                                                                       |
| -------------- | -------------------------- | ------------------------------------------------------------------------------------------ |
| build + PR 证据 | PR | 构建并 `load` 到本地：跑 `scripts/smoke-test.sh`、包清单守门（vs 已发布镜像）、体积报告，包清单作为 artifact；**不推送** |
| publish        | push `main` / dispatch     | 构建、冒烟、推送、cosign 签名、生成 SBOM、建 GitHub Release + 日期 tag                     |
| canary         | 每月一次 + 手动           | `no-cache` 从零构建 + 冒烟；**不推送、不建 tag**；失败或检测到上游变化时开 Issue            |
| dependabot     | 每周一                     | base digest 与 actions 更新 PR                                                             |

`scripts/smoke-test.sh` 断言内容：

1. 工具链存在性与版本：`gcc` / `g++` / `cc` / `c++` 软链指向预期 GCC 主版本；`clang-18` / `lld` / `llvm`、`python3`、`node`、`ccache`、`make`、`rsync`、`unzip`、`git`、`patch` 存在。
2. **上游 host prereq 断言**（来源：`immortalwrt/prereq-build.mk` @ 记录 commit）：`gcc -dumpversion` 匹配 `^(1[0-9]|[2-9][0-9])`、`g++` 同理、`python3 -V` ≥ 3.8、`tar`/`find`/`bash`/`xargs`/`patch`/`diff` 为 GNU 版、`rsync` 可用。
3. 功能性验证：编译并运行带 `pthread` 的 C hello-world；`python3 -m py_compile` 一个临时文件。
4. 产出包清单 diff 报告。

其他：SBOM 每次发布必生成（buildx attestation）；CVE 扫描仅出报告、附在每月 canary 的 Issue 里，**不阻断发布**（工具链镜像 CVE 噪音大且多不可利用）。

## 8. 验收清单（本次优化"完成"的定义）

- [ ] 压缩体积 ≤ 1000 MB（CI 实测）
- [ ] 冒烟测试全绿，且包含上游 prereq 断言与包清单 diff 报告
- [ ] `docs/OPTIMIZATION.md` 与最终实现一致
- [ ] README 增补 4 节：兼容性契约、tag 与 digest 引用语义、镜像内容清单、在自有 CI 中使用（含 `cosign verify` 示例）
- [ ] 定时 canary 与 Dependabot 均已生效并各触发过至少一次
- [ ] 包清单 diff 中不存在"未记录理由的移除"

## 9. 未来升级触发器

- **codename → trixie**：上游停止支持 bookworm，或临近 bookworm 安全支持结束（**2028-06-30**）；trixie 安全支持至 2030-06-30。
- **arm64**：上游脚本放开 `x86_64` 硬检查时重议。
- **第三方源变动**：apt.llvm.org / nodesource / yarn / git-core PPA 一旦停止支持 bookworm，触发 codename 或源策略重议。

## 10. 残余缺口（实施中发现，逐条闭环）

| 缺口 | 影响 | 计划 |
| ---- | ---- | ---- |
| 上游脚本内部两处构建期未固定引用：`padjffs2.c` 取自 `openwrt/openwrt` 的 `main` 分支，`po2lmo` 来自 `openwrt/luci.git` 默认分支的 `git clone` | 同一 commit 可能构建出不同镜像（(b) 未完全达成） | 步骤②：以**独立 patch** 方式固定到具体 commit（vendored 文件保持与上游逐字一致，差异集中在 patch 中，便于上游同步时 diff） |
| 上游脚本没有 `set -e`，中途失败仍可能产出"看似成功"的镜像 | 静默的残缺环境 | 步骤③：由冒烟测试断言工具链齐全来兜底；不修改 vendored 文件本身的错误处理 |
| Dockerfile 的 `Fix Complie Link` 层与上游脚本自身的软链逻辑重复（脚本已 `ln -svf` gcc/g++/gcc-ar/gcc-nm/gcc-ranlib 与 c++） | 冗余层、两处事实源 | 步骤③：冒烟测试到位、能断言软链指向预期版本后，按"先证明再删"处理 |
| `curl` 必须显式留在 `scripts/packages.txt`（脚本在安装任何东西之前就要用它），`ca-certificates` 同理 | 缺失会让脚本所有 HTTPS 拉取失败 | 已在步骤①显式列出并在清单内注释原因（`--no-install-recommends` 会移除 curl 的 Recommends） |

## 11. 风险与对策

| 风险                                     | 对策                                                                     |
| ---------------------------------------- | ------------------------------------------------------------------------ |
| 删包导致少数用户编译特定包失败           | 守门规则（先证明再删）+ tag 不可变，用户可回退引用旧 tag/digest          |
| cosign v2 → v3 破坏性变更                | 双端验证；不通过则暂留 v2.4.3 并记 issue                                 |
| vendored 脚本与上游漂移                  | 每月 canary 检测 + 人工同步流程                                          |
| 上游第三方源不可用导致从零构建失败       | canary 提前发现（不再依赖用户报告）                                      |
