#!/usr/bin/env sh
set -eu

failures=0
TEST_DIR=${TEST_DIR:-tests/errors}

run_case() {
    file="$1"
    expected="$2"
    log="/tmp/l26_error_test_$$.log"

    if ./l26c "$file" >"$log" 2>&1; then
        echo "FAIL $file: expected failure, got success"
        failures=$((failures + 1))
    elif grep -F "$expected" "$log" >/dev/null 2>&1; then
        echo "PASS $file"
    else
        echo "FAIL $file: expected message not found: $expected"
        cat "$log"
        failures=$((failures + 1))
    fi

    rm -f "$log"
}

run_case "$TEST_DIR/duplicate_decl.l26" "duplicate declaration"
run_case "$TEST_DIR/undeclared_var.l26" "undeclared variable"
run_case "$TEST_DIR/type_mismatch_assign.l26" "type mismatch assigning"
run_case "$TEST_DIR/read_set.l26" "read requires int variable"
run_case "$TEST_DIR/add_non_set.l26" "'add' requires a set variable"
run_case "$TEST_DIR/set_ne.l26" "'!=' is not supported for sets"
run_case "$TEST_DIR/set_literal_eq.l26" "set equality requires set variables"
run_case "$TEST_DIR/division_by_zero.l26" "division by zero"

if [ "$failures" -ne 0 ]; then
    echo "$failures error test(s) failed"
    exit 1
fi

echo "All error tests passed"
