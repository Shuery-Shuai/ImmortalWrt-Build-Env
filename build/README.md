# build/

> **归类判据**：本目录 = **Dockerfile 直接 `COPY` 进镜像的构建输入**（apt/dpkg 配置片段 + 包清单）。
> 判定标准是**消费方**，不是文件类型：凡是会被镜像消费的东西放这里；只在流水线里做断言的放 `ci/`，
> 从上游取来并需要版本锁的放 `vendor/`。

## 三个 apt / dpkg 配置片段

| 文件                     | 落点（容器内路径）                                | 解决什么                                                                     |
| ------------------------ | ------------------------------------------------- | ---------------------------------------------------------------------------- |
| `apt-no-recommends.conf` | `/etc/apt/apt.conf.d/99-rtfw-builder`             | 全局关闭 `Install-Recommends` / `Install-Suggests`                           |
| `dpkg-nodoc.conf`        | `/etc/dpkg/dpkg.cfg.d/01-rtfw-builder-nodoc`      | 安装期用 `path-exclude` 就不写入 doc / man / groff / info / lintian / locale |
| `apt-backports.list`     | `/etc/apt/sources.list.d/bookworm-backports.list` | 补上 bookworm-backports 源                                                   |

**为什么必须在第一个 apt 操作之前生效**：这三个片段都是"生效时机敏感"的——它们只在 apt/dpkg
**执行安装的那一刻**才起作用，事后补放对已经装进去的东西毫无影响。所以 Dockerfile 把三个
`COPY` 全部放在第一个 `RUN` 之前（而不是 install 层的末尾），由此它们同时约束后面的
`apt-get full-upgrade`、`apt-get install`，以及 `vendor/init_build_environment.sh` 内部的
`apt install` / `apt full-upgrade`。

- **关闭 Recommends（量化依据见 `docs/OPTIMIZATION.md` §6，也写在片段注释里）**：以本镜像包集合为
  种子，Debian bookworm 的 Depends 闭包为 484 包 / 2.2 GB，Depends + Recommends 闭包为
  1042 包 / 4.8 GB——**仅 Recommends 就引入 558 包 / 2.6 GB**。关掉后被判定"承重"的推荐包
  必须显式补回 `packages.txt`（`openssh-client`、`qemu-block-extra` 等），移除项逐族登记在
  `ci/packages-removed.allow` 并由 CI 守门。
- **`path-exclude` 而不是"装完再 `rm`"**：被排除的文件根本不落盘，省下的是**真实镜像层体积**；
  事后删除只会在同一个层里留下空洞。版权文件 `copyright` 必须保留（许可证合规要求随镜像分发），
  locale 只保留 `C` / `C.UTF-8` / `en*`。
- **backports 源修复的是"静默失败"**：上游脚本只在"中国网络"分支里写入该源，却无条件执行
  `apt update -y -t bookworm-backports` 与一批 `-t bookworm-backports` 安装。源不存在时
  `apt update` 失败，意味着刚配好的第三方源（apt.llvm.org、nodesource、yarn、golang PPA）
  **从未刷新列表**，于是 LLVM 18 / Node / Go 全部装不上——而脚本没有 `set -e`，所以它"成功"退出了。
  该缺陷由 CI 冒烟实测确认（clang 为 14、node 为空、go 缺失），已发布镜像同样存在。

## packages.txt —— 包清单唯一事实源

Dockerfile 只负责读取本文件（`grep -vE \'^[[:space:]]*(#|$)\' /tmp/packages.txt | xargs`），
不在 Dockerfile 里另写一份包名列表。规则（详见 `docs/OPTIMIZATION.md` §5 / §6，也写在清单注释里）：

1. `vendor/init_build_environment.sh` 会安装的包**不在本文件重复列出**（§5「消除两份清单重叠」
   已执行，62 项重复条目已移除）。
2. **例外：脚本自身在安装任何东西之前就要用到的工具必须保留**（`curl`、`ca-certificates`、
   `patch`），否则脚本会先失败——见清单的 bootstrap 段。
3. **删除任何包都需要证据**：dpkg 包清单 diff 报告（旧镜像 vs 新镜像）+ 冒烟测试通过，
   并在 `ci/packages-removed.allow` 登记理由。
4. 只存在于"脚本运行中才配置的源"里的包**不能写进本文件**（写了构建期就 `exit 100`）——
   例如 `llvm-18-dev`，改由 `vendor/patches/0002-add-llvm-dev.patch` 在脚本的 LLVM 安装行补回。

## 已登记文件

| 文件                     | 被谁消费                                        |
| ------------------------ | ----------------------------------------------- |
| `apt-backports.list`     | Dockerfile `COPY` → 镜像内 apt 源               |
| `apt-no-recommends.conf` | Dockerfile `COPY` → 镜像内 apt 配置             |
| `dpkg-nodoc.conf`        | Dockerfile `COPY` → 镜像内 dpkg 配置            |
| `packages.txt`           | Dockerfile `COPY` 后在 `apt-get install` 中读取 |

新增文件请对照本目录开头的**归类判据**：不被 Dockerfile `COPY` 的东西不要放这里。
