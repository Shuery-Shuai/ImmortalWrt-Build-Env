#!/usr/bin/env bash
# 包清单守门（docs/OPTIMIZATION.md §6"先证明再删"）：
# 比较 baseline 与 candidate 两个镜像的 dpkg 包清单，输出新增/移除报告；
# 任何未在 allow 文件登记的"移除"都会导致非零退出，从而阻断 PR。
#
# 用法: scripts/package-diff.sh <baseline-image> <candidate-image> [allow-file]
#   allow-file 默认 scripts/packages-removed.allow
# printf 格式串里的反引号是 Markdown 代码标记，不是命令替换，属 shellcheck SC2016 误报。
# shellcheck disable=SC2016
set -uo pipefail

BASE_IMG="${1:?用法: package-diff.sh <baseline-image> <candidate-image> [allow-file]}"
CAND_IMG="${2:?用法: package-diff.sh <baseline-image> <candidate-image> [allow-file]}"
ALLOW_FILE="${3:-scripts/packages-removed.allow}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

inventory() { # inventory <image> —— 输出已排序的包名清单
	docker run --rm "$1" dpkg-query -W -f='${Package}\n' | sort -u
}

if ! inventory "$BASE_IMG" >"$WORK_DIR/base.txt"; then
	printf '错误: 无法从 baseline 镜像获取包清单: %s\n' "$BASE_IMG" >&2
	exit 2
fi
if ! inventory "$CAND_IMG" >"$WORK_DIR/cand.txt"; then
	printf '错误: 无法从 candidate 镜像获取包清单: %s\n' "$CAND_IMG" >&2
	exit 2
fi

comm -23 "$WORK_DIR/base.txt" "$WORK_DIR/cand.txt" >"$WORK_DIR/removed.txt"
comm -13 "$WORK_DIR/base.txt" "$WORK_DIR/cand.txt" >"$WORK_DIR/added.txt"

ALLOWED="$WORK_DIR/allowed.txt"
if [ -f "$ALLOW_FILE" ]; then
	sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOW_FILE" | grep -v '^$' | sort -u >"$ALLOWED"
else
	: >"$ALLOWED"
fi

# 未登记移除 = 移除列表中不被任何 allow 模式匹配的包（allow 支持 shell 通配，如 texlive-*）
: >"$WORK_DIR/unrecorded.txt"
while IFS= read -r pkg; do
	[ -n "$pkg" ] || continue
	matched=0
	while IFS= read -r pat; do
		[ -n "$pat" ] || continue
		# shellcheck disable=SC2254
		case "$pkg" in $pat) matched=1; break ;; esac
	done <"$ALLOWED"
	[ "$matched" -eq 1 ] || printf '%s\n' "$pkg" >>"$WORK_DIR/unrecorded.txt"
done <"$WORK_DIR/removed.txt"

BASE_N="$(wc -l <"$WORK_DIR/base.txt" | tr -d ' ')"
CAND_N="$(wc -l <"$WORK_DIR/cand.txt" | tr -d ' ')"
REMOVED_N="$(wc -l <"$WORK_DIR/removed.txt" | tr -d ' ')"
ADDED_N="$(wc -l <"$WORK_DIR/added.txt" | tr -d ' ')"
UNREC_N="$(wc -l <"$WORK_DIR/unrecorded.txt" | tr -d ' ')"

report() {
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
		printf '**未登记移除（必须处理）**：请把每个包连同理由写入 `%s`，或在 `scripts/packages.txt` 中恢复它。\n\n```\n' "$ALLOW_FILE"
		cat "$WORK_DIR/unrecorded.txt"
		printf '```\n'
	fi
}

report
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	report >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$UNREC_N" -gt 0 ]; then
	printf '\n包清单守门失败：存在 %s 个未登记的移除。\n' "$UNREC_N" >&2
	exit 1
fi

printf '\n包清单守门通过：无未登记的移除。\n'
