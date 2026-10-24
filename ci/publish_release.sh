#!/usr/bin/env bash
# 发布收尾：创建/复用不可变 CalVer tag，测量镜像体积，生成 Release 说明，
# 再创建或更新 GitHub Release。副作用顺序固定：先推 tag，再写说明文件，最后调 gh。
# 依据：docs/OPTIMIZATION.md §4「版本与 tag（CalVer）」、§5「可复现性」、§7「CI 骨架」
#
# 本脚本从 .github/workflows/docker-publish.yml 的「创建不可变 tag 与 Release」步骤
# 抽出（原为内联 run: | 块）。tag 一旦发布永不重写，本脚本只新增、从不覆盖。
#
# 用法: ci/publish_release.sh [name] [digest]
#   两个入参也可只经环境变量传（位置参数优先，YAML 用 env: 直连更省事）：
#     NAME / RELEASE_NAME      本次发布的不可变 tag（steps.release.outputs.name）
#     DIGEST / RELEASE_DIGEST  已推送镜像的 digest（steps.build-and-push.outputs.digest）
#   必需环境变量：
#     GITHUB_REPOSITORY  <owner>/<repo>，保留大小写（cosign 身份串用它，小写名另算）
#     GITHUB_REF_TYPE    runner 注入；值为 tag 表示本次由 tag 推送触发（不建 tag）
#   可选环境变量：
#     GITHUB_OUTPUT      runner 注入；本步骤无下游消费者，刻意不向其写任何 key
#     NOTES_FILE         说明文件落盘路径，默认 release-notes.md（同内联版本）
#     VERIFY_IMAGE       体积测量的本地镜像引用，默认 rtfw-builder:verify
#     IMG_TAR / IMG_DIR  体积测量的解包路径，默认 /tmp/rel.img.tar 与 /tmp/rel.img
#     RELEASE_DRY_RUN    =1 时跳过对外可见写操作（git tag / git push / gh release），
#                        只打印将要执行的命令；默认不启用，即真实发布行为
#   注意 is_main 不是本步骤的输入：它只服务 Extract Docker metadata 的 latest 别名，
#   「由 tag 触发」这一分支判断沿用内联版本的 GITHUB_REF_TYPE。
#   gh 的凭据沿用 runner 注入的 GH_TOKEN（本脚本不读它，只依赖 gh 自行识别）。
# 输出: 三行信息逐字沿用内联版本（tag 触发 / tag 已存在 / Release 已存在）；
#       入参或必需环境变量缺失退出码 2，其余失败沿用 set -e 的非零退出。
#
# 结构约定（Google Shell Style Guide）：日志出口 → 常量 → 函数（被调用者在前，
# 且按 main 的调用顺序排列）→ main。所有顶层执行语句都在 main 内。
# 说明文本里的反引号是 Markdown 代码标记，不是命令替换，属 shellcheck SC2016 误报。
# shellcheck disable=SC2016

# 有意保留内联版本的 set -euo pipefail：发布中途失败必须让 job 立刻变红
# （tag 已推而 Release 未建是半截状态，靠重跑本步骤自愈）。同族的守门脚本
# （check_structure.sh / package-diff.sh）刻意去掉 -e，是因为它们的契约是
# 「跑完全部断言再汇总」；本步骤没有这种契约，去掉 -e 会引入真实行为差异。
set -euo pipefail

# === 日志出口（必须最先定义，供后面所有函数使用）===

# 向 stderr 输出一行错误信息。
# Args:
#   $*: 消息正文。
log_error() {
	printf '%s\n' "$*" >&2
}

# === 常量与配置（默认值即内联版本的取值）===

# 体积测量对象：PR 与发布共用同一份 Dockerfile 产物（见 workflow 的 verify-build）。
VERIFY_IMAGE_DEFAULT="rtfw-builder:verify"

# docker save 的落盘与解包路径。刻意沿用内联版本的固定路径：同 ref 的发布已由
# job 级 concurrency 串行化，不存在并发互踩。
IMG_TAR_DEFAULT="/tmp/rel.img.tar"
IMG_DIR_DEFAULT="/tmp/rel.img"

# Release 说明文件的默认落盘路径（与内联版本一致，相对当前工作目录）。
NOTES_FILE_DEFAULT="release-notes.md"

# === 入参 ===

# 解析发布入参与环境，全部收进全局变量，供后续函数直接取用。
# Args:
#   $1: 可选，发布 tag；缺省时取 $RELEASE_NAME 或 $NAME。
#   $2: 可选，镜像 digest；缺省时取 $RELEASE_DIGEST 或 $DIGEST。
parse_args() {
	NAME="${1:-${RELEASE_NAME:-${NAME:-}}}"
	DIGEST="${2:-${RELEASE_DIGEST:-${DIGEST:-}}}"
	if [ -z "$NAME" ]; then
		log_error '缺少发布 tag：传位置参数 1，或设置环境变量 NAME / RELEASE_NAME'
		exit 2
	fi
	if [ -z "$DIGEST" ]; then
		log_error '缺少镜像 digest：传位置参数 2，或设置环境变量 DIGEST / RELEASE_DIGEST'
		exit 2
	fi
	if [ -z "${GITHUB_REPOSITORY:-}" ]; then
		log_error '缺少环境变量 GITHUB_REPOSITORY（<owner>/<repo>，Release 与 cosign 身份串都要用）'
		exit 2
	fi
	# GITHUB_REF_TYPE 由 runner 注入；本地缺省时按「非 tag 触发」处理，走幂等建 tag 分支。
	TRIGGERED_BY_TAG="${GITHUB_REF_TYPE:-}"
	NOTES_FILE="${NOTES_FILE:-${NOTES_FILE_DEFAULT}}"
	VERIFY_IMAGE="${VERIFY_IMAGE:-${VERIFY_IMAGE_DEFAULT}}"
	IMG_TAR="${IMG_TAR:-${IMG_TAR_DEFAULT}}"
	IMG_DIR="${IMG_DIR:-${IMG_DIR_DEFAULT}}"
	DRY_RUN="${RELEASE_DRY_RUN:-0}"
}

# 执行一条对外可见的写操作。RELEASE_DRY_RUN=1 时只打印命令本身、不执行，
# 便于本地核对「这次会发生哪些副作用」；默认路径与内联版本完全等价（直接执行）。
# Args:
#   $*: 命令与其参数。
run_side_effect() {
	if [ "$DRY_RUN" = "1" ]; then
		printf '[dry-run] %s\n' "$*"
		return 0
	fi
	"$@"
}

# === tag 与体积 ===

# 创建并推送不可变 tag。两处幂等守卫：由 tag 推送触发时什么都不做；
# tag 本地已存在（上一次半截发布留下的）时跳过创建，直接进 Release 分支补齐。
ensure_tag_pushed() {
	if [ "$TRIGGERED_BY_TAG" = "tag" ]; then
		echo "本次由 tag 推送触发：$NAME"
	elif git rev-parse -q --verify "refs/tags/$NAME" >/dev/null 2>&1; then
		echo "tag $NAME 已存在（可能是上一次部分发布），跳过创建"
	else
		run_side_effect git tag "$NAME"
		run_side_effect git push origin "refs/tags/$NAME"
	fi
}

# 按「逐层 gzip 后相加」的注册表口径算分层压缩合计，把体积文案行写到 stdout。
# 口径与 docs/OPTIMIZATION.md §8 的验收数字一致（822 MB 即此口径）。
# Args:
#   $1: docker image inspect 得到的未压缩字节数。
stack_size_line() {
	local U="$1" TOTAL=0 FILES S f
	# 两种镜像格式：legacy 的 */layer.tar，与 OCI 的 blobs/sha256（只算 >100k 的真层）。
	if compgen -G "$IMG_DIR/*/layer.tar" >/dev/null; then
		FILES=$(find "$IMG_DIR" -name layer.tar)
	else
		FILES=$(find "$IMG_DIR/blobs/sha256" -type f -size +100k 2>/dev/null)
	fi
	# 刻意不引用 $FILES：文件名不含空白（save 产出与 sha256 命名），沿用内联版本逐词展开。
	# shellcheck disable=SC2086
	for f in $FILES; do
		S="$(gzip -6 -c "$f" | wc -c | tr -d ' ')"
		TOTAL=$((TOTAL + S))
	done
	printf '未压缩 %s / 分层 gzip 合计 %s' "$(numfmt --to=iec "$U")" "$(numfmt --to=iec "$TOTAL")"
}

# 测体积并给出 SIZE_LINE。取不到本地验证镜像、或 save+解包失败，都退回固定文案：
# 体积只是报告项，绝不因它阻断发布。
measure_size_line() {
	local U
	SIZE_LINE="(本地验证镜像不可用，未测量)"
	if docker image inspect "$VERIFY_IMAGE" >/dev/null 2>&1; then
		U="$(docker image inspect -f '{{.Size}}' "$VERIFY_IMAGE")"
		if docker save "$VERIFY_IMAGE" -o "$IMG_TAR" &&
			mkdir -p "$IMG_DIR" && tar -xf "$IMG_TAR" -C "$IMG_DIR"; then
			SIZE_LINE="$(stack_size_line "$U")"
		else
			SIZE_LINE="(体积测量失败，已跳过；不影响发布)"
		fi
	fi
}

# === Release 说明与发布 ===

# 生成 Release 说明文件（写到 $NOTES_FILE）。digest 是权威引用、tag 只是别名，
# 因此两者都写进说明；上游脚本 commit 与包清单给复现者留锚点。
write_release_notes() {
	REPO_LC="$(printf '%s' "${GITHUB_REPOSITORY}" | tr '[:upper:]' '[:lower:]')"
	# cosign 校验身份串：内联版本把这串就地写在 echo 里，这里提出来只为把行长压回 100 列内。
	local COSIGN_IDENTITY="https://github.com/${GITHUB_REPOSITORY}/.github/workflows/.*"
	{
		echo "不可变镜像 tag：\`$NAME\`（同 tag 永不重写；需要完全可复现请用 digest 引用）"
		echo ""
		echo "- digest：\`$DIGEST\`"
		echo "- 体积：${SIZE_LINE}"
		echo "- 平台：linux/amd64"
		echo "- 上游构建脚本：\`$(grep '^COMMIT=' vendor/upstream.lock | cut -d= -f2)\`"
		echo "- 包清单：\`build/packages.txt\`（构建产物清单见对应 PR 的 CI 证据报告）"
		echo ""
		echo "### 验证签名"
		echo ""
		echo '```sh'
		echo "cosign verify ghcr.io/${REPO_LC}@${DIGEST} \\"
		echo "  --certificate-identity-regexp '${COSIGN_IDENTITY}' \\"
		echo "  --certificate-oidc-issuer https://token.actions.githubusercontent.com"
		echo '```'
	} >"$NOTES_FILE"
}

# 幂等守卫：Release 已存在（上一次半截发布）就改为更新说明，否则新建。
# gh 从 runner 注入的 GH_TOKEN 取凭据，无需本脚本传递。
publish_release() {
	if gh release view "$NAME" >/dev/null 2>&1; then
		echo "Release $NAME 已存在，改为更新说明"
		run_side_effect gh release edit "$NAME" --notes-file "$NOTES_FILE"
	else
		run_side_effect gh release create "$NAME" --title "$NAME" --notes-file "$NOTES_FILE"
	fi
}

# === main ===

# 入口：解析入参 → 推 tag → 测体积 → 写说明 → 建/改 Release。
# 顺序即内联版本的顺序，不得调换（tag 必须先于 Release 存在，说明文件先于 gh 调用）。
main() {
	parse_args "$@"
	ensure_tag_pushed
	measure_size_line
	write_release_notes
	publish_release
}

main "$@"
