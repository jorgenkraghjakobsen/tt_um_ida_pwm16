#!/usr/bin/env bash
# Stop the demo board UART bridge and hand the REPL back.
#
#   ./stop_bridge.sh [/dev/ttyACM0]
#
# Sends the escape sequence, which the bridge only looks for after a quiet
# period and never in the middle of a command burst.
set -eu
PORT=${1:-/dev/ttyACM0}

python3 - "$PORT" <<'PY'
import sys, time, serial
port = sys.argv[1]
with serial.Serial(port, 115200, timeout=0.3) as s:
    s.reset_input_buffer()
    time.sleep(0.4)                      # the idle gap the bridge waits for
    s.write(b"\x00\xffTTBRK!")
    s.flush()
    time.sleep(0.6)
    s.write(b"\r\n")                     # nudge the REPL into printing a prompt
    time.sleep(0.4)
    out = s.read(400)
print("bridge stopped" if b">>>" in out else
      "sent the escape; if there is still no REPL, unplug and replug the board")
PY
