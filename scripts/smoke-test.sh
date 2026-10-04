#!/usr/bin/env bash
# 镜像内冒烟测试：断言工具链齐全、上游宿主前置条件满足、且真的能编译运行。
# 依据：docs/OPTIMIZATION.md §7
#
# 运行方式（CI 见 .github/workflows/docker-publish.yml）：
#   docker run --rm -v "$PWD/scripts/smoke-test.sh:/smoke-test.sh:ro" <image> bash /smoke-test.sh
#
# 上游前置条件镜像自 immortalwrt/immortalwrt 的 include/prereq-build.mk
#   @ 0a9fcdf5715ffd6cd384775f4a98494026543061
#   （GCC >= 10、Python >= 3.8、GNU 版 tar/find/bash/xargs/patch/diff、rsync）
# 传给 check_ok 的片段刻意用单引号包住，避免在外层 shell 提前展开，属 shellcheck SC2016 误报。
# shellcheck disable=SC2016
set -uo pipefail

PREREQ_COMMIT="0a9fcdf5715ffd6cd384775f4a98494026543061"
PASS=0
FAIL=0

ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

check_cmd() {
	if command -v "$1" >/dev/null 2>&1; then ok "命令存在: $1"; else bad "命令缺失: $1"; fi
}

check_ok() { # check_ok <描述> <bash 片段>：片段退出码为 0 则判定通过
	if bash -c "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}

printf '========================================\n'
printf '冒烟测试开始（容器内）\n'
printf '========================================\n'

printf '\n-- 1. 工具链存在性 --\n'
for c in gcc g++ cc c++ clang clang++ lld make ccache python3 pip3 node npm yarn \
	git patch rsync unzip tar find xargs diff curl wget gawk bison flex \
	upx padjffs2 po2lmo gh go; do
	check_cmd "$c"
done

printf '\n-- 2. 上游宿主要求 (prereq-build.mk @ %s) --\n' "$PREREQ_COMMIT"
GCC_DUMP="$(gcc -dumpversion 2>/dev/null || true)"
if printf '%s' "$GCC_DUMP" | grep -qE '^(1[0-9]|[2-9][0-9])\.?'; then
	ok "gcc -dumpversion='$GCC_DUMP' 满足 GCC >= 10"
else
	bad "gcc -dumpversion='$GCC_DUMP' 不满足 GCC >= 10"
fi

GXX_DUMP="$(g++ -dumpversion 2>/dev/null || true)"
if printf '%s' "$GXX_DUMP" | grep -qE '^(1[0-9]|[2-9][0-9])\.?'; then
	ok "g++ -dumpversion='$GXX_DUMP' 满足 GCC >= 10"
else
	bad "g++ -dumpversion='$GXX_DUMP' 不满足 GCC >= 10"
fi

PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
if [ -n "$PY_VER" ] && [ "$(printf '%s\n3.8\n' "$PY_VER" | sort -V | head -n1)" = "3.8" ]; then
	ok "python3 版本 $PY_VER 满足 >= 3.8"
else
	bad "python3 版本 '$PY_VER' 不满足 >= 3.8"
fi

check_ok "tar 为 GNU 版" "tar --version 2>&1 | grep -q GNU"
check_ok "find 为 GNU 版" "find --version 2>&1 | grep -q GNU"
check_ok "bash 为 GNU 版" "bash --version 2>&1 | grep -q GNU"
check_ok "xargs 为 GNU 版" "xargs -r --version 2>&1 | grep -q GNU"
check_ok "patch 为 GNU 版" "patch --version 2>&1 | grep -q 'Free Software Foundation'"
check_ok "diff 为 GNU 版" "diff --version 2>&1 | grep -q GNU"
check_ok "rsync 可执行" "rsync --version"

printf '\n-- 3. 编译器软链一致性 --\n'
check_ok "/usr/bin/cc 与 /usr/bin/gcc 指向同一目标" '[ "$(readlink -f /usr/bin/cc)" = "$(readlink -f /usr/bin/gcc)" ]'
check_ok "/usr/bin/c++ 与 /usr/bin/g++ 指向同一目标" '[ "$(readlink -f /usr/bin/c++)" = "$(readlink -f /usr/bin/g++)" ]'
check_ok "cc 与 gcc 版本一致" '[ "$(cc -dumpversion)" = "$(gcc -dumpversion)" ]'

printf '\n-- 4. 功能性验证 --\n'
TMP_DIR="$(mktemp -d)" || { bad "无法创建临时目录"; TMP_DIR=""; }
if [ -n "$TMP_DIR" ]; then
	cat >"$TMP_DIR/hello.c" <<'EOF'
#include <pthread.h>
#include <stdio.h>
static void *worker(void *arg) { (void)arg; return (void *)"pthread-ok"; }
int main(void) {
	pthread_t t;
	void *ret;
	if (pthread_create(&t, NULL, worker, NULL) != 0) return 1;
	pthread_join(t, &ret);
	printf("hello %s\n", (char *)ret);
	return 0;
}
EOF
	if gcc -O2 -Wall -Werror -pthread -o "$TMP_DIR/hello" "$TMP_DIR/hello.c" 2>"$TMP_DIR/cc.log"; then
		ok "C 编译（-pthread -Wall -Werror）通过"
		if [ "$("$TMP_DIR/hello")" = "hello pthread-ok" ]; then
			ok "编译产物可运行且 pthread 正常"
		else
			bad "编译产物运行结果异常"
		fi
	else
		bad "C 编译失败（见下方日志）"
		sed 's/^/         /' "$TMP_DIR/cc.log"
	fi

	cat >"$TMP_DIR/hello.cpp" <<'EOF'
#include <string>
#include <iostream>
int main() { std::string s = "cxx-ok"; std::cout << s << std::endl; return 0; }
EOF
	if g++ -O2 -Wall -Werror -o "$TMP_DIR/hello_cpp" "$TMP_DIR/hello.cpp" 2>"$TMP_DIR/cxx.log"; then
		ok "C++ 编译（g++ -Wall -Werror）通过"
	else
		bad "C++ 编译失败（见下方日志）"
		sed 's/^/         /' "$TMP_DIR/cxx.log"
	fi

	printf 'py = 1\n' >"$TMP_DIR/mod.py"
	check_ok "python3 -m py_compile 通过" "python3 -m py_compile '$TMP_DIR/mod.py'"

	rm -rf "$TMP_DIR"
fi

printf '\n-- 5. 环境信息（诊断用）--\n'
printf '  gcc      : %s\n' "$(gcc --version 2>/dev/null | head -n1)"
printf '  clang    : %s\n' "$(clang --version 2>/dev/null | head -n1)"
printf '  python3  : %s\n' "$(python3 -V 2>&1)"
printf '  node     : %s\n' "$(node --version 2>/dev/null)"
printf '  ccache   : %s\n' "$(ccache --version 2>/dev/null | head -n1)"
printf '  llvm dir : %s\n' "$(ls -d /usr/lib/llvm-1* 2>/dev/null || echo '(none)')"

printf '\n-- 6. 用户可见契约（docs/OPTIMIZATION.md §2）--\n'
check_ok "当前用户是 immortalwrt" '[ "$(id -un)" = "immortalwrt" ]'
check_ok "工作目录是 /home/immortalwrt/workdir" '[ "$PWD" = "/home/immortalwrt/workdir" ]'
check_ok "宿主架构为 x86_64（镜像仅支持 amd64）" '[ "$(uname -m)" = "x86_64" ]'
check_ok "sudoers 免密配置存在" '[ -f /etc/sudoers.d/immortalwrt ]'
check_ok "sudo 免密可用" 'sudo -n true'
check_ok "git 全局身份已配置" '[ -n "$(git config --system user.email)" ]'
check_ok "工作目录可写" 'touch .smoke-write-test && rm -f .smoke-write-test'

printf '\n========================================\n'
printf '冒烟测试结束：通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
printf '========================================\n'

[ "$FAIL" -eq 0 ]
