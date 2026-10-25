# RtfwBuilder —— 路由器固件编译环境镜像（基线：Debian bookworm）。
#
# 分层计划（顺序即缓存顺序，也是层间依赖顺序；重排前先读对应层的就地注释）：
#   [1] FROM + SHELL            基线按 digest 固定 + shell 语义收敛
#   [2] LABEL                   OCI 溯源元数据，必须与 [1] 的 digest 一致
#   [3] COPY x3                 apt/dpkg 行为约束 + backports 源（必须先于任何 apt 操作）
#   [4] RUN                     系统准备：apt update + full-upgrade
#   [5] COPY x2                 包清单、vendored 脚本与补丁落 /tmp
#   [6] RUN                     装包 -> 打补丁 -> 执行上游脚本 -> 清 apt lists
#   [7] RUN x2                  builder 用户 + git 系统级身份
#   [8] VOLUME / USER / WORKDIR 运行时契约（docs/OPTIMIZATION.md §2）
#
# 相邻层刻意不合并：[3] 必须早于 [4] 才能约束它，[4] 产生的 /var/lib/apt/lists
# 必须活到 [6] 才能装包；任何合并都会改变“某个文件在何时存在”这一前提。

# 基础镜像按 digest 固定以保证可复现；升级由 Dependabot 每周一提 PR（见 .github/dependabot.yml）。
# 更换 codename（例如 trixie）属于破坏性变更，走 docs/OPTIMIZATION.md §9 的升级触发器流程。
FROM debian:bookworm@sha256:854dd8ab51d62866dbd8f5431d15ce77b12983a2a4a1e1fe43a2395dc7ef9f61

# 行为变更（相对上一版 Dockerfile）：RUN 的执行 shell 由 /bin/sh(dash) 换成 bash -o pipefail，
# 使含管道的 RUN 层（本文件仅 [6]）在管道任意一段失败时报错，而非只看最后一段的退出码。
# pipefail 的能力边界（实测 debian 的 bash 5.2 与本机 bash 5.3.20，结论一致）：它只决定“管道整体退出
#   码取哪一段”，不改变“命令替换的退出码是否传给宿主命令”。处在参数位置的 $(...) 状态一律不外传，
#   实测空清单下旧写法 apt-get 收到 0 个包参数仍 RC=0；同一条管道直接作命令用时 pipefail 下 RC=1、
#   退回 /bin/sh(dash) 则 RC=0——这就是 pipefail 相对旧写法的真实增量，仅此而已。
# 因此本层的 fail-fast 由 [6] 的显式守卫承担，pipefail 只覆盖守卫的前一半：[6] 把管道从参数位置移到
#   简单赋值 VAR="$(cmd)" 右侧，此时赋值退出码等于替换退出码（实测文件缺失 RC=2、提取失败可经 && 中止），
#   空结果（RC=1 或 RC=0）再由 [ -z ] 兜住。若把本 SHELL 退回 /bin/sh(dash)，守卫依旧生效（判空不依赖
#   pipefail），但“管道中段失败”这类错误会重新静默——两者互补，不是互替。
# 位置要求：SHELL 只影响它之后的指令，故必须紧接 FROM、早于任何 RUN（dockerfile 规范）。
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 溯源元数据与 FROM 行严格成对：digest 升级时两行必须同步改，否则 inspect 出的 base 与真实不符。
LABEL org.opencontainers.image.base.name="docker.io/library/debian:bookworm" \
      org.opencontainers.image.base.digest="sha256:854dd8ab51d62866dbd8f5431d15ce77b12983a2a4a1e1fe43a2395dc7ef9f61"

# ---------------------------------------------------------------------------
# [3] apt/dpkg 行为约束：三处 COPY 必须全部早于 [4] 的第一个 apt 操作，否则首层 apt 不受约束。
#     apt/dpkg 在启动时读取这些目录，装包之后再写入已经来不及，故不能挪到 install 层末尾。
# ---------------------------------------------------------------------------
# 关闭推荐包安装 + 安装期不写文档/手册/本地化文件；两个 .conf 文件内有量化依据。
COPY build/apt-no-recommends.conf /etc/apt/apt.conf.d/99-rtfw-builder
COPY build/dpkg-nodoc.conf /etc/dpkg/dpkg.cfg.d/01-rtfw-builder-nodoc
# bookworm-backports 源：上游脚本假设它存在（只在中国网络分支写入），否则 LLVM 18 / Node / Go
# 的安装会静默失败——详见 build/apt-backports.list 的说明（CI 实测确认）。
COPY build/apt-backports.list /etc/apt/sources.list.d/bookworm-backports.list

# ---------------------------------------------------------------------------
# [4] 系统准备层。
# ---------------------------------------------------------------------------
# 保留 /var/lib/apt/lists 是设计而非疏漏：本层只做 update + full-upgrade，真正装包的 [6]
# 要复用这里的 lists，并由 [6] 末尾统一 rm -rf。本层清理会迫使 [6] 重新 update，多一层
# apt lists 且拖慢构建。故 DL3009 在本层不成立，明确抑制而非“修复”。
#
# 刻意不执行 dpkg --add-architecture i386（2026-10-24 移除，先证明再删）：
#   Debian 的 multilib 方案把 32 位库按 i386-linux-gnu 路径装进 **amd64 包**，
#   故 gcc-multilib / g++-multilib / libc6-dev-i386 / lib32gcc-s1 全部是 amd64 架构，
#   单 amd64 索引即可完整提供 -m32 能力。实测（全新 debian:bookworm，无 foreign arch）：
#     dpkg --print-foreign-architectures 为空；上述 4 包从 amd64 索引装成；
#     dpkg -l | grep -c ":i386" = 0；gcc -m32 与 g++ -m32 均编译运行通过（sizeof(void*)=4）。
#   添加 i386 架构的唯一实际效果是强制每个 apt 源提供 binary-i386 索引，而第三方源经常不提供：
#   mirrors.tuna.tsinghua.edu.cn/llvm-apt 的 binary-i386/Packages 返回 404（官方 apt.llvm.org 为 200），
#   上游脚本的中国网络分支正是把 llvm 源改写到该镜像，于是 apt update 报错、LLVM 18 源被丢弃，
#   而脚本无 set -e 会静默产出缺 clang/lld/llvm 的镜像（冒烟 6 项失败，2026-10-24 实测）。
#   撤销条件：若将来确需安装真正的 i386 二进制包（而非 multilib amd64 包），须连同本注释一并复核。
# hadolint ignore=DL3009
RUN apt-get update && \
    apt-get full-upgrade -y

# ---------------------------------------------------------------------------
# [5] 输入物料：包清单 + vendored 上游脚本 + 补丁。
#     单独成层：这些文件变动最频繁，与 [6] 分开可让 [3]/[4] 的缓存继续命中。
# ---------------------------------------------------------------------------
# 包清单唯一事实源：build/packages.txt
# 构建脚本唯一样本：vendor/init_build_environment.sh（vendored，上游 commit 见 vendor/upstream.lock）
COPY build/packages.txt vendor/init_build_environment.sh /tmp/
COPY vendor/patches/ /tmp/patches/

# ---------------------------------------------------------------------------
# [6] 安装层：装包 -> 应用补丁 -> 执行上游脚本 -> 清理（全镜像唯一的 lists 清理处）。
#     补丁必须先于脚本：0002-add-llvm-dev.patch 改的正是脚本第 254 行的 apt install 行。
# ---------------------------------------------------------------------------
# DL3008（逐包 pin 版本）：本仓库的版本锁定哲学不是 apt 层内 pin，而是三重外部约束——
#   基线按 digest 固定（FROM 行）+ 包名单一事实源 build/packages.txt（只列包名，版本由固定后的
#   基线与 backports/第三方源决定）+ Dependabot 每周提 digest 升级 PR（.github/dependabot.yml）。
#   层内 pin 与这三者相互冲突，会造成 apt 无法满足的依赖。
# DL3015（--no-install-recommends）：已由 build/apt-no-recommends.conf 在全局生效
#   （APT::Install-Recommends "false"），实测省下 Recommends 闭包 558 包 / 2.6 GB；该文件在 [3]
#   层就已就位，因此同时约束本层与 vendored 脚本内部的 apt install/full-upgrade，命令行开关
#   只覆盖本层且属重复。承重推荐包已显式列在 build/packages.txt。
# SC2046（命令替换未加引号）：这里的词法拆词正是语义所在——拆出来的就是包名列表。加引号会把
#   整串当一个包名交给 apt-get（"sudo bash curl ..." -> Unable to locate package）直接构建失败，
#   因此必须保持不加引号，不可按提示“修复”。
# 空清单守卫（本层 fail-fast 的所在）：build/packages.txt 是包名单一事实源，一旦它为空或只剩注释，
#   旧写法会让 apt-get 收到 0 个包参数并返回 0（实测），于是镜像带着“只有上游脚本、没有 12 个
#   显式依赖”继续构建成功，缺陷推迟到运行期才暴露。现在三步把它变成构建期失败：
#     1) 提取移到简单赋值：`PKGS="$(...)"` 的退出码即替换的退出码（赋值不是管道，不受位置影响），
#        所以 grep 读不到文件（RC=2）或 xargs 失败会经 && 直接中止本层；
#     2) `[ -z "$PKGS" ]` 兜住“提取成功但结果为空”（纯注释文件时 grep 的 RC=1 也会先被 1) 拦下，
#        这里的判空是纵深，因为空结果本身才是“装不到任何包”的充分条件；
#     3) 拆词交给 `$(printf '%s\n' "$PKGS")`：值先被引号包住（不被二次展开破坏），再由命令替换的
#        默认拆词还原成 N 个参数，与旧写法逐词等价，且 SC2046 仍如实落在这一行、抑制理由不变。
#   顺序不可调换：守卫必须在 apt-get 之前，否则空清单已经“成功”安装完。
#   CI 的包清单闸门（ci/package-diff.sh，见 .github/workflows/docker-publish.yml:337）仍是第二道防线
#   而非第一道：它比对的是两个已构建镜像之间的包差异，空清单产出的镜像对它并非异常输入，且只在 PR/
#   发布流程中运行；本守卫则在每一次 docker build 的最早期就失败，不依赖 CI 是否被触发。
# hadolint ignore=DL3008,DL3015,SC2046
RUN PKGS="$(grep -vE '^[[:space:]]*(#|$)' /tmp/packages.txt | xargs)" && \
    if [ -z "$PKGS" ]; then echo "ERROR: build/packages.txt yielded an empty package list" >&2; exit 1; fi && \
    echo "installing $(printf '%s\n' "$PKGS" | wc -w) packages from build/packages.txt" && \
    apt-get install -y $(printf '%s\n' "$PKGS") && \
    for p in /tmp/patches/*.patch; do \
      echo "applying ${p}"; \
      patch --batch --forward /tmp/init_build_environment.sh < "${p}" || exit 1; \
    done && \
    bash /tmp/init_build_environment.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# [7] 身份与权限。
# ---------------------------------------------------------------------------
# 添加用户 Builder
# 用户名必须是 builder、家目录必须是 /home/builder/workdir：docs/OPTIMIZATION.md §2 的用户可见
# 契约（改名已属破坏性变更），且 README 的 docker run -v 直接依赖该路径。
RUN useradd -m builder -s /bin/bash && \
    echo 'builder ALL=NOPASSWD: ALL' > /etc/sudoers.d/builder

# Configure Git Info
# 用系统级而非 builder 用户级：固件编译会在容器内产生 git 操作，需在任意 HOME 下都可用。
# 邮箱域名 rtfw 仅作占位标识，不用于投递。
RUN git config --system user.name "builder" && \
    git config --system user.email "builder@rtfw"

# ---------------------------------------------------------------------------
# [8] 运行时契约。
# ---------------------------------------------------------------------------
VOLUME [ "/home/builder/workdir" ]

# DL3066（建议数字 UID）：用户名本身是对外契约，不可改成数字——docs/OPTIMIZATION.md §2 固定
#   “容器内用户 builder + 工作目录 /home/builder/workdir”；ci/smoke-test.sh:264 断言
#   [ "$(id -un)" = "builder" ]、:267 断言 -f /etc/sudoers.d/builder，两者都按名字而非 UID 校验，
#   数字 USER 会让冒烟测试与 sudoers.d 文件名同时失效。故保留命名 USER。
# hadolint ignore=DL3066
USER builder
WORKDIR /home/builder/workdir
