#!/usr/bin/env bash
# 包清单守门（docs/OPTIMIZATION.md §6"先证明再删"）：
# 比较 baseline 与 candidate 两个镜像的 dpkg 包清单，输出新增/移除报告；
# 任何未在 allow 文件登记的"移除"都会导致非零退出，从而阻断 PR。
#
# 用法: ci/package-diff.sh <baseline-image> <candidate-image> [allow-file]
#   allow-file 默认 ci/packages-removed.allow
#
# 结构约定（Google Shell Style Guide）：日志出口 → 常量 → 函数（被调用者在前，
# 且按 main 的调用顺序排列）→ main。所有顶层执行语句都在 main 内。
# printf 格式串里的反引号是 Markdown 代码标记，不是命令替换，属 shellcheck SC2016 误报。
# shellcheck disable=SC2016

# 有意不加 -e：报告必须先于退出码产出（守门失败也要把 diff 完整交给 reviewer）。
set -uo pipefail

# === 日志出口（最先定义，供后面所有函数使用）===

# 向 stderr 输出一行错误信息。
# Args:
#   $*: 消息正文。
log_error() {
	printf '%s\n' "$*" >&2
}

# === 常量与配置 ===

# CI 不传第三个参数，因此默认值就是守门数据来源（见 ci/README.md）。
ALLOW_FILE_DEFAULT="ci/packages-removed.allow"

# === 参数与工作目录 ===

# 解析命令行参数为全局变量；缺参数时由 ${n:?} 直接报错退出。
# Args:
#   $@: 原始命令行参数。
parse_args() {
	BASE_IMG="${1:?用法: package-diff.sh <baseline-image> <candidate-image> [allow-file]}"
	CAND_IMG="${2:?用法: package-diff.sh <baseline-image> <candidate-image> [allow-file]}"
	ALLOW_FILE="${3:-${ALLOW_FILE_DEFAULT}}"
}

# 创建临时工作目录并登记退出时清理。
create_workdir() {
	WORK_DIR="$(mktemp -d)"
	trap 'rm -rf "$WORK_DIR"' EXIT
}

# === 采集与比对 ===

# 输出一台镜像中已排序去重的包名清单（写到 stdout）。
# Args:
#   $1: 镜像引用。
inventory() {
	# shellcheck disable=SC2016
	docker run --rm "$1" dpkg-query -W -f='${Package}\n' | sort -u
}

# 采集两侧清单；任一侧取不到即以退出码 2 终止（无法比对 ≠ 通过）。
collect_inventories() {
	if ! inventory "$BASE_IMG" >"$WORK_DIR/base.txt"; then
		log_error "错误: 无法从 baseline 镜像获取包清单: $BASE_IMG"
		exit 2
	fi
	if ! inventory "$CAND_IMG" >"$WORK_DIR/cand.txt"; then
		log_error "错误: 无法从 candidate 镜像获取包清单: $CAND_IMG"
		exit 2
	fi
}

# 由两份清单算出移除集与新增集（comm 要求输入已排序）。
split_removed_and_added() {
	comm -23 "$WORK_DIR/base.txt" "$WORK_DIR/cand.txt" >"$WORK_DIR/removed.txt"
	comm -13 "$WORK_DIR/base.txt" "$WORK_DIR/cand.txt" >"$WORK_DIR/added.txt"
}

# 把 allow 文件规整成纯模式清单（剥注释与空白、去空行、排序去重）；
# 文件不存在则视为空白名单。
load_allow_patterns() {
	ALLOWED="$WORK_DIR/allowed.txt"
	if [ -f "$ALLOW_FILE" ]; then
		sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOW_FILE" |
			grep -v '^$' | sort -u >"$ALLOWED"
	else
		: >"$ALLOWED"
	fi
}

# 未登记移除 = 移除列表中不被任何 allow 模式匹配的包（allow 支持 shell 通配，如 texlive-*）。
find_unrecorded_packages() {
	local pkg pat matched
	: >"$WORK_DIR/unrecorded.txt"
	while IFS= read -r pkg; do
		[ -n "$pkg" ] || continue
		matched=0
		while IFS= read -r pat; do
			[ -n "$pat" ] || continue
			# 故意不引用 $pat：需要 shell 通配展开语义（SC2254）。
			# shellcheck disable=SC2254
			case "$pkg" in $pat)
				matched=1
				break
				;;
			esac
		done <"$ALLOWED"
		[ "$matched" -eq 1 ] || printf '%s\n' "$pkg" >>"$WORK_DIR/unrecorded.txt"
	done <"$WORK_DIR/removed.txt"
}

# 统计各项数量（供报告与守门判断使用）。
compute_counts() {
	BASE_N="$(wc -l <"$WORK_DIR/base.txt" | tr -d ' ')"
	CAND_N="$(wc -l <"$WORK_DIR/cand.txt" | tr -d ' ')"
	REMOVED_N="$(wc -l <"$WORK_DIR/removed.txt" | tr -d ' ')"
	ADDED_N="$(wc -l <"$WORK_DIR/added.txt" | tr -d ' ')"
	UNREC_N="$(wc -l <"$WORK_DIR/unrecorded.txt" | tr -d ' ')"
}

# === 报告与守门 ===

# 渲染 Markdown 形式的包清单 diff 报告（写到 stdout）。
render_report() {
	printf '### 包清单 diff\n\n'
	printf '| 项 | 值 |\n| --- | --- |\n'
	printf '| baseline | `%s`（%s 个包） |\n' "$BASE_IMG" "$BASE_N"
	printf '| candidate | `%s`（%s 个包） |\n' "$CAND_IMG" "$CAND_N"
	printf '| 新增 | %s |\n' "$ADDED_N"
	printf '| 移除 | %s |\n' "$REMOVED_N"
	printf '| 未登记移除 | %s |\n\n' "$UNREC_N"
	if [ "$ADDED_N" -gt 0 ]; then
		printf '<details><summary>新增（%s）</summary>\n\n```\n' "$ADDED_N"
		cat "$WORK_DIR/added.txt"
		printf '```\n\n</details>\n\n'
	fi
	if [ "$REMOVED_N" -gt 0 ]; then
		printf '<details><summary>移除（%s）</summary>\n\n```\n' "$REMOVED_N"
		cat "$WORK_DIR/removed.txt"
		printf '```\n\n</details>\n\n'
	fi
	if [ "$UNREC_N" -gt 0 ]; then
		printf '**未登记移除（必须处理）**：请把每个包连同理由写入 `%s`，或在 `build/packages.txt` 中恢复它。\n\n```\n' "$ALLOW_FILE"
		cat "$WORK_DIR/unrecorded.txt"
		printf '```\n'
	fi
}

# 输出报告到 stdout；若存在 GITHUB_STEP_SUMMARY 则同时追加一份。
publish_report() {
	render_report
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		render_report >>"$GITHUB_STEP_SUMMARY"
	fi
}

# 守门判断：存在未登记移除即失败（退出码 1，阻断 PR 合并）。
enforce_gate() {
	if [ "$UNREC_N" -gt 0 ]; then
		log_error ""
		log_error "包清单守门失败：存在 $UNREC_N 个未登记的移除。"
		exit 1
	fi
	printf '\n包清单守门通过：无未登记的移除。\n'
}

# === main ===

# 入口：采集 → 比对 → 登记校验 → 报告 → 守门。
main() {
	parse_args "$@"
	create_workdir
	collect_inventories
	split_removed_and_added
	load_allow_patterns
	find_unrecorded_packages
	compute_counts
	publish_report
	enforce_gate
}

main "$@"
