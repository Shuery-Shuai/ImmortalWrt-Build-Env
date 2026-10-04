# 一次性验证记录（2026-10-04）

## 方法

在正式 PR 之前，用**临时**的一次性验证通道（位于临时分支 `verify/scratch` 的 `verify-only.yml`，
由 `smokeverify*` tag 触发，验证完成后即删除）
在 GitHub runner 上执行**真实的无缓存构建 + 镜像内冒烟 + 包清单守门 + 体积测量**。
该通道**不推送任何镜像、不签名、不建 Release**，产物回写到 `verify/scratch` 分支供匿名读取。

## 结果（第十五次运行，评审修复后的最终态）

| 项目 | 结果 |
| ---- | ---- |
| 从零构建（no-cache） | ✅ 成功 |
| 镜像内冒烟 | ✅ **59 项断言全过**（评审后新增 3 条 LLVM 18 断言） |
| 包清单守门（对比已发布镜像） | ✅ 386 项移除、**0 项未登记**（候选镜像 516 个包） |
| 体积 | 2.7 GB 未压缩 / **822 MB 分层 gzip 合计（注册表口径）** —— 验收标准 ≤ 1000 MB **已达成** |
| 上游漂移检测 | ✅ 锁定 commit 与上游 master 一致（该步骤为 canary 的组成，已单独验证） |
| canary 滚动 Issue 逻辑 | ✅ 同一段代码连跑两次，分别覆盖**新建**与**追加评论**两条路径（Issue #17，comments=1） |
| CVE 扫描（trivy） | ✅ 步骤可用：620 项 HIGH/CRITICAL（588 HIGH / 32 CRITICAL），按共识**只报告不阻断** |
| cosign v3 签名 / 验签 | ✅ 端到端通过（本地注册表）：keyless 签名 + 与 README/workflow 相同的验签参数均成功 |
| SBOM / provenance attestation | ✅ **生成**已验证（buildkit 调用 syft scanner 并导出 attestation manifest）；⚠️ **推送未验证**——两次本地尝试均败于脚手架限制：① buildx 的 BuildKit 跑在容器内，`127.0.0.1` 够不到宿主注册表（需用 bridge IP）；② 非 localhost 的明文 HTTP 注册表需额外 insecure-registry 配置（buildx 默认只对 localhost 放行 HTTP）。真实发布走 GHCR 的 HTTPS，不受这两点影响，但推送本身仍待真实发布确认 |

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

## 评审驱动的修复（第十一至十五次验证）

独立双轴评审（Standards / Spec 各一个子代理，互不共享上下文）在合并前抓出 6 处文档与实现脱节，逐条修复并复验：

| 问题 | 处置 |
| ---- | ---- |
| §5 声称"消除两份清单重叠"，实际 `packages.txt` 仍是原清单逐字提取（与脚本重复 62 项） | 移除 62 项；保留 4 个 **bootstrap 例外**并注明原因：`curl`、`ca-certificates`（脚本自身在安装前要用）、`patch`（Dockerfile 在脚本前就要应用补丁）、`qemu-utils`（见下） |
| §10 承诺"冒烟到位后删掉与脚本重复的 `Fix Complie Link` 层"，层仍在 | 删除该层，§10 标记闭环；由冒烟（cc/gcc、c++/g++ 一致性）与守门验证 |
| dispatch 带 tag 输入时不再产出任何镜像 tag（真实 bug） | 改为 tag 推送 / dispatch 带 tag / dispatch 留空（CalVer）三种情况都在步骤内判定 |
| §7 要求 canary"每月 1 日 + 手动"，实际只有 schedule | 新增 dispatch 布尔输入 `canary` |
| §4 要求 Release 说明含体积，实际缺失 | Release 说明写入未压缩体积与分层 gzip 合计 |
| §7 要求冒烟断言 clang-18 / llvm，实际只查存在性 | 新增 3 条断言（clang 版本为 18、`/usr/lib/llvm-18`、`llvm-config` 为 18） |

**实施过程中我自己引入并修掉的两个回归**（均由 CI 实测发现，如实记录）：

1. `patch` 被当作"上游脚本会装的包"删除 → Dockerfile 的补丁循环跑在脚本之前，构建以 exit 127 失败。
   修复：`patch` 列为 bootstrap 例外。
2. `qemu-utils` 同样被删除 → backports 的 `qemu-block-extra` 依赖是 `qemu-system-any | qemu-utils`（二选一），
   失去第二个分支后 apt 只能选第一个，把整套 QEMU 系统模拟器拖了进来（**+53 包 / +72 MB**）。
   修复：`qemu-utils` 列为 bootstrap 例外，包数与体积回到 516 / 822 MB。

另有一次**交付分支污染**：临时验证 workflow 因我一次误操作被 amend 进 ②b 并传播到 ③b、④，已清除并重排；
`docs/OPTIMIZATION.md` §8 的"临时验证文件不得混入主干内容"检查项现已在最终校验中通过。

## 尚未验证的部分（需真实发布）

- CalVer 不可变 tag 的创建、GitHub Release 生成（都需要真实发布才会发生；PR 评论发布已在 PR #19 上验证通过）。
- buildx 的 SBOM / provenance attestation **推送**到真实注册表（生成已验证，见上表）。
- 注册表实际存储的压缩体积（本地测得的分层 gzip 合计 822 MB 已是同口径代理）。

## 残留

- 体积验收以**注册表分层压缩合计**为准（822 MB 目前只是整包 gzip 估算），需在首次发布后核对。
- 上游脚本内部的失败静默问题（无 `set -e`）未被修改：vendored 文件保持与上游逐字一致，
  由冒烟断言兜底（这正是本次能发现第 2 条缺陷的原因）。
