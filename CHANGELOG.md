# Changelog

本项目的所有重要变更都记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
版本标识使用日期式不可变 tag `bookworm-YYYY.MM.DD[.n]`（语义见 README 的「镜像 tag 与引用语义」）。

## [未发布]

### 新增

- CI 证据设施：PR 上执行冒烟测试、包清单守门（对比上一版已发布镜像）与体积报告，
  并把报告作为 PR 评论发布、同时上传为 artifact。
- 每月 1 日 04:00 UTC 的从零构建巡检（canary）：`no-cache` 构建 + 冒烟 + 上游脚本漂移检测
  - trivy CVE 扫描（CRITICAL/HIGH，仅报告、不阻断）；每月发布一条**滚动 Issue** 记录结果，
    不推送、不建 tag。
- 发布时生成 SBOM attestation；cosign 升级到 v3 并新增"签名后立即 verify"的校验步骤。
- Dependabot：`docker` 与 `github-actions` 两个生态，每周一提 PR。
- `docs/OPTIMIZATION.md`：优化共识、验收清单与残余缺口。
- 冒烟测试覆盖上游宿主前置条件（`immortalwrt/prereq-build.mk @ 0a9fcdf`：GCC ≥ 10、
  Python ≥ 3.8、GNU 工具集、rsync）与真实编译运行验证。
- 新增 CI `lint` job（job 图首位，`build` 需 `lint`+`structure`、`canary` 需 `lint`）：
  hadolint 查 Dockerfile、actionlint 查 `.github/workflows/`、yamllint 查 workflows 与
  `.github/dependabot.yml`。工具镜像按 `tag@digest` 固定：
  `hadolint/hadolint:v2.15.1-alpine@sha256:a1d49ae1…`、
  `rhysd/actionlint:1.7.12@sha256:b1934ee5…`；yamllint 走 `pip install yamllint==1.38.0`
  装进 `RUNNER_TEMP` 下的 venv；
  **刻意不引入任何新的第三方 action**（`uses:` 集合与本轮之前逐字一致，Dependabot 的攻击面不变）。
  分级策略：只有 error 级发现阻断，style/warning/info 只打印并写进 Step Summary。
  配置在 `.github/lint/hadolint.yml` 与 `.github/lint/yamllint.yml`。
- 新增 `ci/check_structure.sh`（目录结构守门）与 `ci/publish_release.sh`（发布收尾）：原本是 workflow
  里最大的两个内联 `run: |` 块，抽出后可在 checkout 根用 `bash ci/<name>.sh` 本地执行并复现同一退出码，
  且纳入 shellcheck 覆盖。文件登记清单（`ALLOWED_ROOT` / `ALLOW_build` / `ALLOW_vendor` /
  `ALLOW_ci`）自此只住在本仓库唯一事实源 `ci/check_structure.sh` 顶部，不再在 workflow 里。
- 新增 yamllint 风格收敛：`.github/dependabot.yml` 补文档起始符 `---`（该文件只多这一行）。

### 修复

- **基础镜像旧 digest 已下架，从零构建卡死**：`FROM` 固定的
  `sha256:f37a335e…` 已从 Docker Hub 移除，`docker pull` 永久停在首层 0B，构建无法推进。
  已更新为当前索引 digest `sha256:854dd8ab…`，`LABEL org.opencontainers.image.base.digest`
  同步更新（两者必须成对，否则 inspect 出的 base 与真实不符）。
  实测：同一 Dockerfile 由「37 分钟仍失败」变为 189 秒成功构建，hadolint 零告警。
- **i386 架构声明使 LLVM 18 静默丢失（行为变更）**：`dpkg --add-architecture i386` 的唯一实际效果
  是强制每个 apt 源提供 `binary-i386` 索引，而第三方源经常不提供。
  上游脚本的中国网络分支会把 apt.llvm.org 改写到 `mirrors.tuna.tsinghua.edu.cn/llvm-apt`，
  该站点的 `binary-i386/Packages` 返回 404（官方站为 200），导致 `apt update` 报错、
  LLVM 源被丢弃；脚本无 `set -e`，于是静默产出缺 clang/lld/llvm 的镜像（冒烟 6 项失败）。
  现移除该架构声明——Debian 的 multilib 把 32 位库装进 **amd64 包**，单 amd64 索引即可提供
  `-m32`。实测（全新 debian:bookworm，无 foreign arch）：4 个 multilib 包均从 amd64 索引装成，
  `dpkg -l | grep -c ":i386"` = 0，`gcc -m32` / `g++ -m32` 编译运行通过（`sizeof(void*)=4`）。
  **能力不变**：`-m32` 仍可用；移除的仅是一条冗余架构声明。
- **已发布镜像缺少 LLVM 18 / Node / Go**：上游脚本在非中国网络下不写入 bookworm-backports 源，
  却用 `-t bookworm-backports` 执行 `apt update` 与安装，失败又被脚本的"无 `set -e`"吞掉。
  现已显式提供该源，镜像补回 clang-18 / nodejs 22 / golang-1.25 / python3-requests 等 51 个包。
- **`llvm-18-dev` 位置错误**：它只存在于 apt.llvm.org（脚本运行中才配置），写在 `scripts/packages.txt`
  会导致构建期 apt exit 100；改由 `scripts/patches/0002-add-llvm-dev.patch` 在脚本的 LLVM 安装行补回。
- **包清单守门的基线镜像名大小写错误**：GHCR 要求全小写，此前一直静默跳过，现已真正执行。
- 移除与上游脚本重复的 Debian LLVM/Clang 14 全套（冒烟确认 clang/lld 仍可用且为 18）。
- actionlint 发现从 1 条收敛到 0 条：`cosign sign --yes {}@${DIGEST}` 的 SC2086 以加引号修复
  （`cosign sign --yes "{}@${DIGEST}"`）。DIGEST 形如 `sha256:` + 64 位十六进制，不含空白与通配字符，
  加引号不改变展开结果。
- **空包清单不再"静默构建成功"（行为变更）**：`build/packages.txt` 为空、只剩注释或文件缺失时，
  旧 Dockerfile 把 `$(grep -vE '^[[:space:]]*(#|$)' /tmp/packages.txt | xargs)` 放在
  `apt-get install -y` 的**参数位置**，命令替换的退出码不外传，于是 apt 收到 0 个包参数仍返回 0：
  构建成功，但镜像少了 12 个显式依赖，缺陷推迟到运行期才暴露。现在 [6] 层把提取移到简单赋值
  `PKGS="$(…)"` 并加 `[ -z "$PKGS" ]` 判空。实测（fake apt-get + `bash -o pipefail`）：真实清单
  RC=0 且 12 个包按序到达 apt；空清单 RC=1、纯注释 RC=1、文件缺失 RC=2，三种失败都碰不到 apt。
  **镜像内容不变**：同一批 12 个包、同一顺序，§2 用户可见契约未受影响。

### 变更

- **Dockerfile 重排为分层计划版（46 → 135 行）**：文件头新增 [1]..[8] 分层计划注释，逐层就地写明
  "为什么不能合并/挪动"。14 条原有指令全部保留、顺序不变，只新增恰好 1 条指令（SHELL）；仍是 4 个 RUN、
  5 个 COPY，除 [6] 外所有 RUN 主体与上一版逐字节一致。镜像内容不变。
- **RUN 执行 shell 由 /bin/sh(dash) 换成 `bash -o pipefail`（行为变更 #1）**：`SHELL ["/bin/bash",
"-o", "pipefail", "-c"]` 紧跟 FROM。此前含管道的 RUN 层只看最后一段的退出码；现在管道任意一段失败即报错。
  能力边界已实测记录在 Dockerfile 就地注释：处在参数位置的 `$(...)` 状态一律不外传，所以本项只补齐守卫的
  前一半，真正的 fail-fast 由上面「修复」里的空清单守卫承担。hadolint 的 DL4006 由此**真正修掉**而非抑制
  （删掉 SHELL 行它就重新报告，实测确认）。
- hadolint 收敛到**零发现**：3 条 `hadolint ignore` 指令覆盖 5 个规则编号，各自带就地理由
  （DL3009 = apt lists 刻意从 [4] 活到 [6]；DL3008+DL3015+SC2046 = 版本锁定哲学是"基线 digest +
  `build/packages.txt` 单一事实源 + Dependabot"、Recommends 已由
  `build/apt-no-recommends.conf` 全局关闭、词法拆词正是包名列表的语义；DL3066 = 用户名
  `builder` 是 `ci/smoke-test.sh` 按名字断言的对外契约），配置在
  `.github/lint/hadolint.yml`（ignored 为空）。
- workflow 瘦身 618 → 575 行：两个最大的内联 `run: |` 块分别替换为 `run: bash ci/check_structure.sh` 与
  `run: bash ci/publish_release.sh`。**流水线语义未变**：触发器、workflow env、各 job 的 runs-on/
  permissions/concurrency/if、步骤顺序、secrets、`steps.*.outputs` 接线、meta tags/labels 逻辑与
  `cosign verify` 步骤全部照旧，`uses:` 的集合也逐字不变（已用 diff 验证）；全文件 `run:` 的差异
  只有两处抽取与上面的 cosign 加引号。
- CI 脚本重组（行为不变）：`ci/smoke-test.sh` 148 → 289 行，顶层流程拆成 21 个函数 + `main`，
  重复的 gcc/g++ 版本检查合并为一个参数化函数，日志原语（`ok`/`bad`）按房内约定最先定义；
  与 HEAD 版在本机（非镜像宿主）跑出的 stdout **逐字节一致**（2650 字节）、退出码相同、
  同为 42 通过 / 17 失败。`ci/package-diff.sh` 96 → 179 行，13 个函数 + `main`，守门语义未变，
  并按 7 个用例重新验证退出码（未登记移除 1 / 全允许 0 / 清单取不到 2 / 写 GITHUB_STEP_SUMMARY 1 /
  默认 allow 路径 1 / 无移除 0 / 缺参数 1）。两个脚本都保持 0755，`shellcheck ci/*.sh` 全绿。
- YAML 风格收敛到 yamllint 零发现（`lint` job 起用后）：`line-length.max` 放宽到 **120 列是明确决策**——
  每个 action 都钉在 40 位 commit SHA 上，一行 `uses:` 装不下 80 列，钉 SHA 优先于 80 列规则；
  `truthy.check-keys: false` 也带理由抑制——GitHub Actions 要求裸 `on:` 键，写成 `"on":` 会改变 Actions
  语义。document-start 由两个 YAML 文件补 `---` 解决（`.github/dependabot.yml` 恰好只多这一行），
  15 条 comment-spacing 以「行内注释前两个空格」修复（SHA 与版本注释文字未变），2 条真超 120 列的行折行，
  剩余 1 条 143 字符行是拆不开的 docs.github.com URL 注释。
- workflow 文案统一为中文（本轮明确要求）：22 行英文说明性注释全部译成中文（另 6 行上游 URL 注释按原样
  保留），12 个英文步骤显示名全部改为中文、原有 16 个中文步骤显示名逐字不动——其中 3 个被 docs 引用，
  「包清单守门 vs 已发布镜像 (PR only)」「冒烟测试」「目录结构守门」今后也不得改写。workflow 名
  `Docker Publish` 与 artifact 标识符 `ci-evidence-pr-<number>`（是标识符不是显示文案）同样保持不变。
- 基础镜像改为**按 digest 固定**（不再使用浮动的 `debian:bookworm`）。
- 上游构建脚本改为 **vendored**（`scripts/init_build_environment.sh` + `scripts/upstream.lock`），
  不再在构建期 `curl | bash` 拉取远端脚本。
- 包清单抽出为唯一事实源 `scripts/packages.txt`；apt 关闭 Recommends/Suggests，
  并在安装期用 dpkg `path-exclude` 剔除 doc/man/info/locale（保留 copyright 与 C/en\* locale）。
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
