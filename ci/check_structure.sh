#!/usr/bin/env bash
# 目录结构守门：断言旧的 scripts 目录已彻底消失、仓库根无游离顶层项、
# build/ vendor/ ci/ 之下全部已登记。
# 依据：docs/OPTIMIZATION.md §7「CI 骨架」（结构不对就不要浪费一次镜像构建）
#
# 本脚本从 .github/workflows/docker-publish.yml 的 structure job 抽出（原为内联
# run: | 块）。抽出后可在本地直接执行同一份断言并复现同一退出码。
#
# 用法: ci/check_structure.sh          # 无参数；必须在仓库根（checkout 根）执行
# 输入: 无参数。数据来自
#         git ls-files
#         git ls-files --others --exclude-standard
#       以及本文件顶部的 ALLOWED_ROOT / ALLOW_build / ALLOW_vendor / ALLOW_ci 清单。
# 输出: 失败时向 stdout 打印 ::error:: 注解 + 归类判据，退出码 1；
#       通过时打印「结构守门通过：…（检查 N 个文件）」，退出码 0。
# 登记方式: 新增文件 = 把路径加进本文件顶部对应的 ALLOW_* 清单（清单即数据，
#           改完直接跑 ci/check_structure.sh 本地复验）。
#
# 与内联块的文本差异（有意为之，且仅此一处）：失败时打印的归类判据末行，原文指向
# .github/workflows/docker-publish.yml 的 ALLOW_* 清单；抽出后清单已在本文件顶部，
# 那句会把维护者引向一个不再含清单的文件，故改指本文件。其余输出逐字一致。
#
# 结构约定（Google Shell Style Guide）：日志出口 → 常量（守门清单）→
# 检查函数（按 main 的调用顺序排列）→ 判定 → main。
# 除计数器初始化外，所有顶层执行语句都在 main 内。

# 有意不加 -e：守门的契约是"跑完全部三项检查再汇总"，任何一条 ::error:: 都必须
# 计入 FAILED 而不是中断执行（退出码在末尾统一给出，一次看全所有违规）。
set -uo pipefail

# === 日志出口（必须最先定义，供后面所有函数使用）===
FAILED=0

# 输出一条 GitHub Actions 错误注解（自动加 ::error:: 前缀）。
# 刻意写 stdout 而非 stderr：内联版本用的是 echo，日志与注解的交错顺序必须逐字一致。
# Args:
#   $*: 注解正文（不含前缀）。
log_error() {
	echo "::error::$*"
}

# === 常量与守门清单（数据即清单，新增文件在此登记）===

# 失败时随 ::error:: 一起打印的归类判据。
# 除末行登记方式外逐字沿用内联版本。那一行是有意改动（见文件头「文本差异」）：
# 抽出后 ALLOW_* 清单已住在本文件顶部，再指向 yml 会把人引向一个不含清单的文件。
# ::error:: 各行的文案、归类判据正文与退出码全部不变。
CRITERIA='归类判据（新增文件必须归入下面三者之一，不要在仓库根放业务文件）：
  build/  = Dockerfile 直接 COPY 进镜像的构建输入（apt/dpkg 配置片段 + 包清单）
  vendor/ = vendored 的上游构建脚本本体 + 版本锁 + 对它的补丁
  ci/     = 只在 CI 里跑的校验脚本 + 校验脚本读的守门数据
仓库根允许项：Dockerfile、README.md、CHANGELOG.md、LICENSE、docs/、build/、vendor/、ci/、.github/
登记方式：在 ci/check_structure.sh 顶部对应的 ALLOW_* 清单中加入该路径。'

# 仓库根允许的顶层项（目录不带斜杠）。
ALLOWED_ROOT='Dockerfile
README.md
CHANGELOG.md
LICENSE
docs
.github
build
vendor
ci'

# build/ 之下已登记文件。
ALLOW_build='build/README.md
build/apt-backports.list
build/apt-no-recommends.conf
build/dpkg-nodoc.conf
build/packages.txt'

# vendor/ 之下已登记文件。
ALLOW_vendor='vendor/README.md
vendor/init_build_environment.sh
vendor/upstream.lock
vendor/patches/0001-pin-extra-artifacts.patch
vendor/patches/0002-add-llvm-dev.patch'

# ci/ 之下已登记文件。
ALLOW_ci='ci/README.md
ci/check_structure.sh
ci/package-diff.sh
ci/packages-removed.allow
ci/publish_release.sh
ci/smoke-test.sh'

# === 工具函数 ===

# 判断某路径是否出现在多行清单中（空行忽略，精确匹配）。
# Args:
#   $1: 待查路径。
#   $2: 多行清单。
in_list() { # in_list <path> <多行清单>
	local line
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		[ "$1" = "$line" ] && return 0
	done <<<"$2"
	return 1
}

# 采集待检查的文件清单（已跟踪 + 未跟踪）。
collect_files() {
	# 已跟踪 + 未跟踪（--exclude-standard 尊重 .gitignore）都要查，
	# 否则本地新建但尚未 git add 的游离文件会溜过去。
	FILES="$({
		git ls-files
		git ls-files --others --exclude-standard
	} | sort -u)"
}

# === 三项检查（按 main 的调用顺序排列）===

# 1) 旧目录 scripts 必须彻底消失（磁盘 + index 两侧都断言）
check_old_scripts_dir() {
	if [ -e scripts ]; then
		log_error '旧 scripts 目录仍存在（磁盘）—— 已按消费方拆分为 build/ + vendor/ + ci/'
		FAILED=1
	fi
	while IFS= read -r f; do
		case "$f" in
			scripts*)
				log_error "旧 scripts 目录下仍有文件：$f —— 请改放到 build/ vendor/ ci/ 之一"
				FAILED=1
				;;
		esac
	done <<<"$FILES"
}

# 2) 仓库根不得有未登记的顶层项
check_root_entries() {
	local top
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		top="${f%%/*}"
		in_list "$top" "$ALLOWED_ROOT" || {
			log_error "仓库根存在未登记项：$f（顶层 $top）"
			FAILED=1
		}
	done <<<"$FILES"
}

# 3) build/ vendor/ ci/ 之下只能是各自已登记文件（未登记说明它放错了目录）
check_subdir_entries() {
	local ALLOW DIR
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		case "$f" in
			build/*)
				ALLOW="$ALLOW_build"
				DIR=build
				;;
			vendor/*)
				ALLOW="$ALLOW_vendor"
				DIR=vendor
				;;
			ci/*)
				ALLOW="$ALLOW_ci"
				DIR=ci
				;;
			*) continue ;;
		esac
		in_list "$f" "$ALLOW" || {
			log_error "$DIR/ 下有未登记文件：$f —— 对照归类判据确认它是否放错目录，或在本步骤登记它"
			FAILED=1
		}
	done <<<"$FILES"
}

# === 判定与汇总 ===

# 守门失败：打印归类判据并给出总注解后以退出码 1 终止（阻断后续 job）。
report_failure() {
	printf '\n%s\n' "$CRITERIA"
	log_error '目录结构守门失败'
	exit 1
}

# 守门通过：打印通过行，带上本次实际检查的文件数。
report_success() {
	printf '结构守门通过：旧 scripts 目录已消失，仓库根无游离顶层项，build/ vendor/ ci/ 之下全部已登记（检查 %s 个文件）。\n' \
		"$(printf '%s\n' "$FILES" | grep -c .)"
}

# === main ===

# 入口：采集清单 → 三项检查 → 判定。任何一项失败即非零退出。
main() {
	collect_files
	check_old_scripts_dir
	check_root_entries
	check_subdir_entries
	if [ "$FAILED" -ne 0 ]; then
		report_failure
	fi
	report_success
}

main
