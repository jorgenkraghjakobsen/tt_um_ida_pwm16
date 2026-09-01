#!/usr/bin/env bash
# End to end bring up of tt_um_ida_pwm16 over UART, using the ucom CLI.
#
# Works against the FPGA test build and against the real chip on the TT demo
# board - it is the same RTL and the same protocol either way.
#
#   ./bringup.sh                 auto detect the port
#   ./bringup.sh -p /dev/ttyUSB1
#
# ucom picks up .reg_file_pwm16 from this directory, which is a symlink to the
# file the register map generator writes.  That is why register names work.

set -u
cd "$(dirname "$0")"

UCOM=${UCOM:-ucom}
OPTS="$@"
pass=0; fail=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

rd()  { $UCOM $OPTS -o h r "$1" 2>/dev/null | tr -d '[:space:]'; }
wr()  { $UCOM $OPTS w "$@" >/dev/null 2>&1; }

expect() {  # expect <what> <got> <want>
    local got=$(echo "$2" | tr 'A-Z' 'a-z' | sed 's/^0x//')
    local want=$(echo "$3" | tr 'A-Z' 'a-z' | sed 's/^0x//')
    if [ "$got" = "$want" ]; then ok "$1 = 0x$want"; else bad "$1: got 0x$got, expected 0x$want"; fi
}

command -v $UCOM >/dev/null || { echo "ucom not found in PATH (see github.com/jorgenkraghjakobsen/ucom)"; exit 1; }

step "1. Is anyone home?"
expect "ctrl.chip_id"  "$(rd ctrl.chip_id)"  "16"
expect "ctrl.version"  "$(rd ctrl.version)"  "01"

step "2. Scratch register walk - proves reads and writes really move data"
for v in 00 a5 5a ff; do
    wr ctrl.scratch 0x$v
    expect "scratch 0x$v" "$(rd ctrl.scratch)" "$v"
done

step "3. Reset state - every channel should sit at centre"
centred=1
for ch in $(seq 0 15); do
    [ "$(rd pwm.ch$ch | sed 's/^0x//')" = "80" ] || centred=0
done
[ $centred = 1 ] && ok "all 16 channels read 0x80" || bad "not all channels are at 0x80 (has something already moved them?)"

step "4. Block write and block read the whole channel section"
$UCOM $OPTS w 0x10 0x10 0x20 0x30 0x40 0x50 0x60 0x70 0x80 \
                   0x90 0xA0 0xB0 0xC0 0xD0 0xE0 0xF0 0xFF >/dev/null 2>&1
back=$($UCOM $OPTS -o h r 0x10 16 2>/dev/null | tr -d '\n')
echo "  read back: $back"
expect "pwm.ch0"  "$(rd pwm.ch0)"  "10"
expect "pwm.ch7"  "$(rd pwm.ch7)"  "80"
expect "pwm.ch15" "$(rd pwm.ch15)" "ff"

step "5. ctrl.center_all - one write, all sixteen back to 1.5 ms"
wr ctrl.center_all 1
expect "pwm.ch0"  "$(rd pwm.ch0)"  "80"
expect "pwm.ch11" "$(rd pwm.ch11)" "80"
expect "strobe reads back 0" "$(rd ctrl.center_all)" "00"

step "6. Sweep - watch the servos, or scope uo[1]"
for v in 00 40 80 c0 ff 80; do
    $UCOM $OPTS w 0x10 0x$v 0x$v 0x$v 0x$v 0x$v 0x$v 0x$v 0x$v \
                       0x$v 0x$v 0x$v 0x$v 0x$v 0x$v 0x$v 0x$v >/dev/null 2>&1
    printf '  all channels -> 0x%s\n' "$v"
    sleep 0.4
done
ok "sweep completed"

step "7. Per channel enable"
wr ctrl.chan_en_l 0x00
expect "chan_en_l off" "$(rd ctrl.chan_en_l)" "00"
sleep 0.5
wr ctrl.chan_en_l 0xFF
expect "chan_en_l on"  "$(rd ctrl.chan_en_l)" "ff"

printf '\n\033[1mResult: %d passed, %d failed\033[0m\n' $pass $fail
[ $fail -eq 0 ]
