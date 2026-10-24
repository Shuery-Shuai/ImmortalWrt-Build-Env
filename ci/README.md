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

## packages-removed.allow —— 移除白名单（守门数据）

`package-diff.sh` 读取的数据文件，本身不是脚本。规则（以文件头注释为权威）：

- 每行一个包名，`#` 之后写移除理由；注释与行内空白会被剥掉后才参与匹配。
- 模式支持 **shell 通配**（例如 `texlive-*`、`*-doc`、`clang-14*`），用于一次性登记同族包；
  **能用具体包名就不要用通配**，理由必须写清适用范围。
- 空清单 = 不允许任何移除。
- CI 的真实 diff 才是权威：漏登记会让 CI 失败并逐个报出，**多登记无害**；
  该文件不得包含 `build/packages.txt` 里显式要求的任何包。

## 已登记文件

| 文件 | 消费方 |
| ---- | ---- |
| `package-diff.sh` | `docker-publish.yml` 的「包清单守门」步骤（需 0755 可执行位） |
| `smoke-test.sh` | `docker-publish.yml` 的「冒烟测试」步骤，build 与 canary 各一处（需 0755） |
| `packages-removed.allow` | `package-diff.sh` 的默认 allow 文件 |
