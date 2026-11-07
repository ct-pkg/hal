#!/usr/bin/env bash
#
# tests/run.sh - the hal package gate.
#
# hal ships no implementation, so every positive test drives the contract
# through a fake backend under tests/support/. Each program prints
# `checks=<n> failures=<n>`; the gate requires a zero exit and `failures=0`.
# Four negative cases assert that the documented compile-time constraints
# still fail with the documented diagnostics.
#
#   bash tests/run.sh
#   CT=/path/to/ct bash tests/run.sh
#
# Exit code 0 means every positive program and every negative case passed.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CT="${CT:-/tmp/ct-0.20.0-worktree/ct}"
if [ ! -x "$CT" ] && ! command -v "$CT" >/dev/null 2>&1; then
    echo "ct not found: $CT (set CT=/path/to/ct)" >&2
    exit 1
fi

work="${TMPDIR:-/tmp}"
work="${work%/}/ct-hal-tests.$$"
rm -rf "$work"
mkdir -p "$work" || exit 1

pass=0
checks=0
neg=0
fail=0
pos_total=0
neg_total=0

ok()  { printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "ct: $CT"
echo

run_positive() {
    name="$1"
    src="$2"
    pos_total=$((pos_total + 1))
    bin="$work/$name.bin"
    outdir="$work/obj-$name"
    log="$work/$name.build.log"

    if ! "$CT" build -I . -I tests --cflags "-Wall -Wextra" \
            --outdir "$outdir" "$src" -o "$bin" >"$log" 2>&1; then
        bad "$name" "build failed: $(tail -n 3 "$log" | tr '\n' ' ')"
        return
    fi
    if grep -q 'warning:' "$log"; then
        bad "$name" "compiler warning: $(grep 'warning:' "$log" | head -n 1)"
        return
    fi
    if ! "$bin" >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name" "nonzero exit: $(tail -n 5 "$work/$name.out" "$work/$name.err" | tr '\n' ' ')"
        return
    fi

    line="$(grep -E '^checks=[0-9]+ failures=[0-9]+$' "$work/$name.out" | tail -n 1)"
    if [ -z "$line" ]; then
        bad "$name" "no summary line in the output"
        return
    fi
    c="${line#checks=}"
    c="${c%% *}"
    f="${line##*failures=}"
    if [ "$f" -ne 0 ] || [ "$c" -le 0 ]; then
        bad "$name" "$line"
        return
    fi

    checks=$((checks + c))
    pass=$((pass + 1))
    ok "$name ($c checks)"
}

run_negative() {
    name="$1"
    expect="$2"
    shift 2
    neg_total=$((neg_total + 1))
    log="$work/neg-$name.log"

    if "$@" >"$log" 2>&1; then
        bad "$name" "expected a nonzero exit, got 0"
        return
    fi
    if ! grep -qF -- "$expect" "$log"; then
        bad "$name" "missing '$expect': $(tail -n 3 "$log" | tr '\n' ' ')"
        return
    fi
    neg=$((neg + 1))
    ok "$name"
}

echo "== Uart: send/recv semantics and buffer boundaries =="
run_positive t_uart tests/t_uart.ct
run_positive t_bounds tests/t_bounds.ct

echo
echo "== dispatch: boxing, two implementations, one trait variable =="
run_positive t_dispatch tests/t_dispatch.ct
run_positive t_allfake tests/t_allfake.ct

echo
echo "== Gpio: read/write and state persistence =="
run_positive t_gpio tests/t_gpio.ct

echo
echo "== Log: written content is assertable =="
run_positive t_log tests/t_log.ct

echo
echo "== Clock: hal::Clock.nowMs() through a stepping stub =="
run_positive t_clock tests/t_clock.ct

echo
echo "== compile-time constraints (negative cases) =="
run_negative check_hct "requires multi-file mode" \
    "$CT" check tests/support/MemUart.h.ct
run_negative notpub_trait "HiddenImpl_Hidden_vtable" \
    "$CT" build -I . -I tests/neg --outdir "$work/obj-neg-hidden" \
    tests/neg/box_hidden.ct -o "$work/neg-hidden.bin"
run_negative box_clock "a static trait has no interface value" \
    "$CT" build -I . --outdir "$work/obj-neg-boxclock" \
    tests/neg/box_clock.ct -o "$work/neg-boxclock.bin"
run_negative bare_clock "use of an undeclared variable" \
    "$CT" build -I . --outdir "$work/obj-neg-bareclock" \
    tests/neg/bare_clock.ct -o "$work/neg-bareclock.bin"

echo
if [ "$fail" -ne 0 ]; then
    printf 'hal: %d/%d positive programs (%d checks), %d/%d negative cases, %d failure(s)\n' \
        "$pass" "$pos_total" "$checks" "$neg" "$neg_total" "$fail"
    echo "logs: $work"
    exit 1
fi
rm -rf "$work"
printf 'hal: %d/%d positive programs (%d checks), %d/%d negative cases, 0 failures\n' \
    "$pass" "$pos_total" "$checks" "$neg" "$neg_total"
