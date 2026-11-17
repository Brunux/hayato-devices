#!/bin/bash
# Tiny dependency-free assertion harness shared by the devices test files.
#
# Each test file sources this, runs its cases (usually in a subshell so a
# library's `die` cannot end the run), and ends with `finish`. Results go to a
# file as well as the terminal because a test case inside `( ... )` must still
# be counted by the parent shell.

TESTS_LOG="${TESTS_LOG:-$(mktemp)}"
: >"$TESTS_LOG"

pass() {
	printf 'ok\t%s\n' "$*" >>"$TESTS_LOG"
	printf '  ok   %s\n' "$*"
}

fail() {
	printf 'fail\t%s\n' "$*" >>"$TESTS_LOG"
	printf '  FAIL %s\n' "$*" >&2
}

assert_eq() {
	local expected="$1" actual="$2" what="$3"
	if [ "$expected" = "$actual" ]; then
		pass "$what"
	else
		fail "$what: expected [$expected], got [$actual]"
	fi
}

assert_ne() {
	local unexpected="$1" actual="$2" what="$3"
	if [ "$unexpected" != "$actual" ]; then
		pass "$what"
	else
		fail "$what: did not expect [$unexpected]"
	fi
}

assert_contains() {
	local haystack="$1" needle="$2" what="$3"
	case "$haystack" in
	*"$needle"*) pass "$what" ;;
	*) fail "$what: [$needle] not in [$haystack]" ;;
	esac
}

assert_not_contains() {
	local haystack="$1" needle="$2" what="$3"
	case "$haystack" in
	*"$needle"*) fail "$what: found [$needle] in [$haystack]" ;;
	*) pass "$what" ;;
	esac
}

assert_true() {
	local what="$1"
	shift
	if "$@"; then pass "$what"; else fail "$what"; fi
}

assert_false() {
	local what="$1"
	shift
	if "$@"; then fail "$what"; else pass "$what"; fi
}

expect_status() {
	local expected="$1" what="$2"
	shift 2
	local out status
	out="$("$@" 2>&1)"
	status=$?
	if [ "$status" -eq "$expected" ]; then
		pass "$what"
	else
		fail "$what: expected status $expected, got $status: $out"
	fi
}

finish() {
	local total failed
	total="$(wc -l <"$TESTS_LOG" | tr -d ' ')"
	failed="$(grep -c '^fail' "$TESTS_LOG" || true)"
	rm -f "$TESTS_LOG"
	printf '\n%d test(s), %d failed\n' "$total" "$failed"
	[ "$failed" -eq 0 ]
}
