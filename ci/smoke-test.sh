#!/usr/bin/env bash
# 镜像内冒烟测试：断言工具链齐全、上游宿主前置条件满足、且真的能编译运行。
# 依据：docs/OPTIMIZATION.md §7
#
# 运行方式（CI 见 .github/workflows/docker-publish.yml）：
#   docker run --rm -v "$PWD/ci/smoke-test.sh:/smoke-test.sh:ro" <image> bash /smoke-test.sh
#
# 上游前置条件镜像自 immortalwrt/immortalwrt 的 include/prereq-build.mk
#   @ 0a9fcdf5715ffd6cd384775f4a98494026543061
#   （GCC >= 10、Python >= 3.8、GNU 版 tar/find/bash/xargs/patch/diff、rsync）
#
# 结构约定（Google Shell Style Guide）：日志出口 → 常量 → 断言原语 →
# 分组断言（按 main 的调用顺序排列）→ main。所有顶层执行语句都在 main 内。
# 传给 check_ok 的片段刻意用单引号包住，避免在外层 shell 提前展开，
# 属 shellcheck SC2016 误报。
# shellcheck disable=SC2016

# 有意不加 -e：本脚本的契约是"跑完全部断言再汇总"，任何断言失败都必须
# 计入 FAIL 而不是中断执行（退出码在末尾统一给出）。
set -uo pipefail

# === 日志出口（必须最先定义，供后面所有函数使用）===
PASS=0
FAIL=0

# 汇报单项通过，并累加通过计数。
# Args:
#   $1: 通过项描述。
ok() {
	printf '  [ OK ] %s\n' "$1"
	PASS=$((PASS + 1))
}

# 汇报单项失败，并累加失败计数。
# Args:
#   $1: 失败项描述。
bad() {
	printf '  [FAIL] %s\n' "$1"
	FAIL=$((FAIL + 1))
}

# 打印开始横幅。
print_banner() {
	printf '========================================\n'
	printf '冒烟测试开始（容器内）\n'
	printf '========================================\n'
}

# 打印结束汇总。
print_summary() {
	printf '\n========================================\n'
	printf '冒烟测试结束：通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
	printf '========================================\n'
}

# === 常量与配置 ===
# prereq-build.mk 的上游 commit，随输出打印，便于回溯断言依据。
PREREQ_COMMIT="0a9fcdf5715ffd6cd384775f4a98494026543061"

# 第 1 组要求存在的命令；顺序即输出顺序（见 ci/README.md）。
REQUIRED_COMMANDS=(
	gcc g++ cc c++ clang clang++ lld make ccache python3 pip3 node npm yarn
	git patch rsync unzip tar find xargs diff curl wget gawk bison flex
	upx padjffs2 po2lmo gh go
)

# === 断言原语 ===

# 断言 PATH 中存在某个命令。
# Args:
#   $1: 命令名。
check_cmd() {
	if command -v "$1" >/dev/null 2>&1; then
		ok "命令存在: $1"
	else
		bad "命令缺失: $1"
	fi
}

# 执行一段 bash 片段，退出码为 0 即判定通过。
# Args:
#   $1: 断言描述。
#   $2: 交给 bash -c 的片段。
check_ok() {
	if bash -c "$2" >/dev/null 2>&1; then
		ok "$1"
	else
		bad "$1"
	fi
}

# 断言 gcc 系列的 -dumpversion 满足上游要求的 GCC >= 10。
# 原先 gcc/g++ 两处判断逐字重复，现合并为一个参数化函数。
# Args:
#   $1: 编译器命令名（gcc 或 g++）。
check_gcc_family_at_least_10() {
	local dump
	dump="$("$1" -dumpversion 2>/dev/null || true)"
	if printf '%s' "$dump" | grep -qE '^(1[0-9]|[2-9][0-9])\.?'; then
		ok "$1 -dumpversion='$dump' 满足 GCC >= 10"
	else
		bad "$1 -dumpversion='$dump' 不满足 GCC >= 10"
	fi
}

# 断言 python3 满足上游要求的 >= 3.8（用 sort -V 做版本比较）。
check_python_at_least_38() {
	local py_ver
	py_ver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
	if [ -n "$py_ver" ] &&
		[ "$(printf '%s\n3.8\n' "$py_ver" | sort -V | head -n1)" = "3.8" ]; then
		ok "python3 版本 $py_ver 满足 >= 3.8"
	else
		bad "python3 版本 '$py_ver' 不满足 >= 3.8"
	fi
}

# === 分组断言（按 main 的调用顺序排列）===

# 第 1 组：工具链存在性。
check_toolchain_presence() {
	printf '\n-- 1. 工具链存在性 --\n'
	local c
	for c in "${REQUIRED_COMMANDS[@]}"; do
		check_cmd "$c"
	done
}

# 第 2 组：上游宿主机前置条件（prereq-build.mk）。
check_upstream_prereqs() {
	printf '\n-- 2. 上游宿主要求 (prereq-build.mk @ %s) --\n' "$PREREQ_COMMIT"
	check_gcc_family_at_least_10 gcc
	check_gcc_family_at_least_10 g++
	check_python_at_least_38
	check_ok "tar 为 GNU 版" "tar --version 2>&1 | grep -q GNU"
	check_ok "find 为 GNU 版" "find --version 2>&1 | grep -q GNU"
	check_ok "bash 为 GNU 版" "bash --version 2>&1 | grep -q GNU"
	check_ok "xargs 为 GNU 版" "xargs -r --version 2>&1 | grep -q GNU"
	check_ok "patch 为 GNU 版" "patch --version 2>&1 | grep -q 'Free Software Foundation'"
	check_ok "diff 为 GNU 版" "diff --version 2>&1 | grep -q GNU"
	check_ok "rsync 可执行" "rsync --version"
}

# 第 2b 组：LLVM 18（上游脚本安装的版本，非 Debian 自带的 14）。
check_llvm18() {
	printf '\n-- 2b. LLVM 18（上游脚本安装的版本，§7 要求断言）--\n'
	check_ok "clang 版本为 18" 'clang --version | grep -q "clang version 18"'
	check_ok "llvm-18 目录存在" '[ -d /usr/lib/llvm-18 ]'
	check_ok "llvm-config 可用且为 18" 'llvm-config --version | grep -q "^18"'
}

# 第 3 组：编译器软链一致性。
check_compiler_symlinks() {
	printf '\n-- 3. 编译器软链一致性 --\n'
	check_ok "/usr/bin/cc 与 /usr/bin/gcc 指向同一目标" \
		'[ "$(readlink -f /usr/bin/cc)" = "$(readlink -f /usr/bin/gcc)" ]'
	check_ok "/usr/bin/c++ 与 /usr/bin/g++ 指向同一目标" \
		'[ "$(readlink -f /usr/bin/c++)" = "$(readlink -f /usr/bin/g++)" ]'
	check_ok "cc 与 gcc 版本一致" '[ "$(cc -dumpversion)" = "$(gcc -dumpversion)" ]'
}

# 写入带 pthread 的 C 探针源码。
# Args:
#   $1: 探针目录。
write_c_probe() {
	cat >"$1/hello.c" <<'EOF'
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
}

# 编译并运行 C 探针：验证 -pthread 可用且产物真能执行。
# Args:
#   $1: 探针目录。
check_c_pthread_probe() {
	local dir="$1"
	write_c_probe "$dir"
	if gcc -O2 -Wall -Werror -pthread -o "$dir/hello" "$dir/hello.c" 2>"$dir/cc.log"; then
		ok "C 编译（-pthread -Wall -Werror）通过"
		if [ "$("$dir/hello")" = "hello pthread-ok" ]; then
			ok "编译产物可运行且 pthread 正常"
		else
			bad "编译产物运行结果异常"
		fi
	else
		bad "C 编译失败（见下方日志）"
		sed 's/^/         /' "$dir/cc.log"
	fi
}

# 写入 C++ 探针源码（string + iostream）。
# Args:
#   $1: 探针目录。
write_cxx_probe() {
	cat >"$1/hello.cpp" <<'EOF'
#include <string>
#include <iostream>
int main() { std::string s = "cxx-ok"; std::cout << s << std::endl; return 0; }
EOF
}

# 用 g++ 编译 C++ 探针。
# Args:
#   $1: 探针目录。
check_cxx_probe() {
	local dir="$1"
	write_cxx_probe "$dir"
	if g++ -O2 -Wall -Werror -o "$dir/hello_cpp" "$dir/hello.cpp" 2>"$dir/cxx.log"; then
		ok "C++ 编译（g++ -Wall -Werror）通过"
	else
		bad "C++ 编译失败（见下方日志）"
		sed 's/^/         /' "$dir/cxx.log"
	fi
}

# 用 python3 -m py_compile 编译一个临时模块。
# Args:
#   $1: 探针目录。
check_python_compile_probe() {
	local dir="$1"
	printf 'py = 1\n' >"$dir/mod.py"
	check_ok "python3 -m py_compile 通过" "python3 -m py_compile '$dir/mod.py'"
}

# 第 4 组：功能性验证——真编译、真运行。临时目录建不出来也只记失败不中断。
check_functional_compile() {
	printf '\n-- 4. 功能性验证 --\n'
	local tmp_dir
	tmp_dir="$(mktemp -d)" || {
		bad "无法创建临时目录"
		tmp_dir=""
	}
	if [ -n "$tmp_dir" ]; then
		check_c_pthread_probe "$tmp_dir"
		check_cxx_probe "$tmp_dir"
		check_python_compile_probe "$tmp_dir"
		rm -rf "$tmp_dir"
	fi
}

# 第 5 组：环境信息（仅诊断输出，不断言）。
print_environment_info() {
	printf '\n-- 5. 环境信息（诊断用）--\n'
	printf '  gcc      : %s\n' "$(gcc --version 2>/dev/null | head -n1)"
	printf '  clang    : %s\n' "$(clang --version 2>/dev/null | head -n1)"
	printf '  python3  : %s\n' "$(python3 -V 2>&1)"
	printf '  node     : %s\n' "$(node --version 2>/dev/null)"
	printf '  ccache   : %s\n' "$(ccache --version 2>/dev/null | head -n1)"
	printf '  llvm dir : %s\n' "$(ls -d /usr/lib/llvm-1* 2>/dev/null || echo '(none)')"
}

# 第 6 组：用户可见契约（docs/OPTIMIZATION.md §2）。
check_user_visible_contract() {
	printf '\n-- 6. 用户可见契约（docs/OPTIMIZATION.md §2）--\n'
	check_ok "当前用户是 builder" '[ "$(id -un)" = "builder" ]'
	check_ok "工作目录是 /home/builder/workdir" '[ "$PWD" = "/home/builder/workdir" ]'
	check_ok "宿主架构为 x86_64（镜像仅支持 amd64）" '[ "$(uname -m)" = "x86_64" ]'
	check_ok "sudoers 免密配置存在" '[ -f /etc/sudoers.d/builder ]'
	check_ok "sudo 免密可用" 'sudo -n true'
	check_ok "git 全局身份已配置" '[ -n "$(git config --system user.email)" ]'
	check_ok "工作目录可写" 'touch .smoke-write-test && rm -f .smoke-write-test'
}

# === main ===

# 冒烟测试入口：按组顺序执行全部断言，末尾汇总并给出退出码。
main() {
	print_banner
	check_toolchain_presence
	check_upstream_prereqs
	check_llvm18
	check_compiler_symlinks
	check_functional_compile
	print_environment_info
	check_user_visible_contract
	print_summary
	[ "$FAIL" -eq 0 ]
}

main
