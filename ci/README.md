# ci/

> **归类判据**：本目录 = **只在 CI 里跑的校验脚本 + 校验脚本读的守门数据**。
> 判定标准是**消费方**，不是文件类型：凡属"不进镜像、只在流水线里做断言或产出报告"的东西放这里。

## package-diff.sh —— 包清单守门

依据 `docs/OPTIMIZATION.md` §6「先证明再删」。调用方是 `.github/workflows/docker-publish.yml`
的「包清单守门 vs 已发布镜像 (PR only)」步骤，以**上一版已发布镜像**（`ghcr.io/…:latest`，
仓库名转小写）为 baseline，比较两个镜像的 `dpkg-query` 包清单。

- **守门语义：任何"未登记的移除"即失败**（退出码 1，阻断 PR 合并）。被移除的包必须先在
  `packages-removed.allow` 里连同理由登记；新增不阻断，只进报告。
- 报告同时写入 `$GITHUB_STEP_SUMMARY`、PR 的 `ci-report.md`（再作为 PR 评论发布并上传 artifact）。
- 拉不到 baseline 镜像时**跳过并显著标注**，绝不静默通过；取不到某一侧包清单退出码 2。
- 调用方式（CI **不传**第三个参数，所以默认值就是守门数据来源，必须指向本目录的 allow 文件）：

  ```sh
  bash ci/package-diff.sh <baseline-image> <candidate-image>   # allow-file 默认 ci/packages-removed.allow
  ```

## smoke-test.sh —— 镜像内冒烟测试

依据 `docs/OPTIMIZATION.md` §7。由 CI 以只读挂载方式在容器内执行（`build` 与 `canary` 两个 job 都用它）：

```sh
docker run --rm -v "$PWD/ci/smoke-test.sh:/smoke-test.sh:ro" <image> bash /smoke-test.sh
```

断言分 6 组，末尾汇总"通过 N 项，失败 M 项"，**有任何失败即非零退出**：

1. **工具链存在性**：`gcc` / `g++` / `cc` / `c++` / `clang` / `clang++` / `lld` / `make` / `ccache` /
   `python3` / `pip3` / `node` / `npm` / `yarn` / `git` / `patch` / `rsync` / `unzip` / `tar` / `find` /
   `xargs` / `diff` / `curl` / `wget` / `gawk` / `bison` / `flex` / `upx` / `padjffs2` / `po2lmo` / `gh` / `go`。
2. **上游宿主前置条件**（`immortalwrt/immortalwrt` 的 `include/prereq-build.mk` @ `0a9fcdf`）：
   `gcc` / `g++` 的 `-dumpversion` 满足 ≥ 10、`python3` ≥ 3.8、`tar` / `find` / `bash` / `xargs` /
   `patch` / `diff` 为 GNU 版、`rsync` 可用；并断言 LLVM 18（`clang version 18`、`/usr/lib/llvm-18`
   存在、`llvm-config --version` 为 18）——这是上游脚本装的版本，不是 Debian 自带的 14。
3. **编译器软链一致性**：`/usr/bin/cc` 与 `/usr/bin/gcc` 同目标、`/usr/bin/c++` 与 `/usr/bin/g++`
   同目标、`cc` 与 `gcc` 版本一致。
4. **功能性验证**：真编译并运行带 `pthread` 的 C hello-world（`-Wall -Werror`）、`g++` 编译 C++
   （string + iostream）、`python3 -m py_compile` 一个临时文件。
5. **环境信息**（仅诊断输出，不断言）。
6. **用户可见契约**（§2）：当前用户 `builder`、工作目录 `/home/builder/workdir`、宿主架构
   `x86_64`（镜像仅支持 amd64）、`/etc/sudoers.d/builder` 存在、`sudo -n true` 免密可用、
   git 全局身份已配置、工作目录可写。

> [!NOTE]
> 包清单 diff 报告由 `package-diff.sh` 这个独立 CI 步骤产出，**不在冒烟脚本内**。

## check_structure.sh —— 目录结构守门

断言三件事：旧 `scripts/` 目录彻底消失（磁盘与 index 两侧都查）、仓库根没有未登记的顶层项、
`build/` `vendor/` `ci/` 之下只有各自已登记的文件（归类判据见本目录开头）。

调用方是 `.github/workflows/docker-publish.yml` 的 `structure` job（「目录结构守门」步骤，跑在
`build` 之前，只查路径不建镜像）。本脚本原先是该 job 的内联 `run: |` 块，抽出后
**文件登记清单（`ALLOWED_ROOT` / `ALLOW_build` / `ALLOW_vendor` / `ALLOW_ci`）住在本文件顶部**，
新增文件就在这里加一行——登记动作不再发生在 workflow 里。

- 数据只有 `git ls-files` 与 `git ls-files --others --exclude-standard`：无参数、不联网、不读镜像。
- 契约是"跑完三项检查再汇总"，因此刻意不加 `set -e`；任何一条 `::error::` 都以退出码 1 阻断后续 job。
- 与内联块的文本差异**只有一处**：失败信息末行的登记指引原指向 `.github/workflows/docker-publish.yml`，
  抽出后清单已不在那里，故改指本文件；其余 `::error::` 文案、归类判据正文与退出码逐字不变。

  ```sh
  bash ci/check_structure.sh   # 必须在 checkout 根执行；0 = 结构合规，1 = 有未登记项并打印归类判据
  ```

## publish_release.sh —— 发布收尾

创建（或复用）不可变 CalVer tag、按注册表口径测镜像体积、生成 Release 说明、创建或更新
GitHub Release。调用方是 `.github/workflows/docker-publish.yml` 的「创建不可变 tag 与 Release」步骤；
原先是内联 `run: |` 块，抽出后 Release 说明正文与内联版本逐字一致。

- 只新增、从不覆盖 tag。三处幂等：由 tag 推送触发时不动 git；tag 本地已存在时跳过创建；
  Release 已存在时改为 `gh release edit` 更新说明。中途失败的半截状态靠重跑本步骤自愈。
- 体积只是报告项：取不到本地验证镜像、或 `docker save` 加解包失败，都退回固定文案，绝不因它阻断发布。
- 入参或必需环境变量缺失（tag / digest / `GITHUB_REPOSITORY`）退出码 2；其余失败沿用 `set -euo pipefail`。
- 可选 `RELEASE_DRY_RUN=1` **只跳过对外可见写操作**（`git tag` / `git push` / `gh release`），
  把将要执行的命令原样打印，其余逻辑与真实发布完全一致——本地核对副作用用它。

  ```sh
  RELEASE_DRY_RUN=1 bash ci/publish_release.sh <tag> <digest>   # 不写外部系统
  bash ci/publish_release.sh <tag> <digest>                     # 真实发布（CI 经 env: 传 NAME/DIGEST）
  ```

## packages-removed.allow —— 移除白名单（守门数据）

`package-diff.sh` 读取的数据文件，本身不是脚本。规则（以文件头注释为权威）：

- 每行一个包名，`#` 之后写移除理由；注释与行内空白会被剥掉后才参与匹配。
- 模式支持 **shell 通配**（例如 `texlive-*`、`*-doc`、`clang-14*`），用于一次性登记同族包；
  **能用具体包名就不要用通配**，理由必须写清适用范围。
- 空清单 = 不允许任何移除。
- CI 的真实 diff 才是权威：漏登记会让 CI 失败并逐个报出，**多登记无害**；
  该文件不得包含 `build/packages.txt` 里显式要求的任何包。

## 已登记文件

| 文件                     | 消费方                                                                     |
| ------------------------ | -------------------------------------------------------------------------- |
| `package-diff.sh`        | `docker-publish.yml` 的「包清单守门」步骤（需 0755 可执行位）              |
| `smoke-test.sh`          | `docker-publish.yml` 的「冒烟测试」步骤，build 与 canary 各一处（需 0755） |
| `packages-removed.allow` | `package-diff.sh` 的默认 allow 文件                                        |
| `check_structure.sh`     | `docker-publish.yml` 的 `structure` job（「目录结构守门」步骤，需 0755）   |
| `publish_release.sh`     | `docker-publish.yml` 的「创建不可变 tag 与 Release」步骤（需 0755）        |
