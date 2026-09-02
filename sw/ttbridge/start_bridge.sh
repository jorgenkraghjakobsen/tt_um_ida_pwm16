#!/usr/bin/env bash
# Start the demo board UART bridge, then let go of the port.
#
#   ./start_bridge.sh [PORT] [CLOCK_HZ]
#
# Afterwards the same device node is the project's UART:
#   ucom -p /dev/ttyACM0 r ctrl.chip_id      -> 0x16
#
# Press RUN on the demo board to stop the bridge and get the REPL back.
set -eu
cd "$(dirname "$0")"
PORT=${1:-/dev/ttyACM0}
CLOCK=${2:-10000000}
MPREMOTE=${MPREMOTE:-mpremote}

echo "copying tt_uart_bridge.py to the demo board on $PORT"
$MPREMOTE connect "$PORT" fs cp tt_uart_bridge.py :tt_uart_bridge.py

echo "starting the bridge (detached, clock ${CLOCK} Hz)"
$MPREMOTE connect "$PORT" exec --no-follow \
    "import tt_uart_bridge; tt_uart_bridge.run(clock_hz=${CLOCK})"

# The SDK startup prints a banner.  Read until the READY sentinel so the port is
# drained and we know setup finished before anything tries to talk registers.
python3 - "$PORT" <<'PY'
import sys, time, serial

port = sys.argv[1]
deadline = time.time() + 20
buf = b""
with serial.Serial(port, 115200, timeout=0.2) as s:
    while time.time() < deadline:
        chunk = s.read(256)
        if chunk:
            buf += chunk
            if b"<<TT-UART-BRIDGE-READY>>" in buf:
                line = buf.split(b"<<TT-UART-BRIDGE-READY>>")[1].split(b"\n")[0]
                print("bridge ready" + (" " + line.decode(errors="replace").strip() if line.strip() else ""))
                if b"SETUP-FAILED" in buf:
                    print("WARNING: board setup reported a failure:")
                    for l in buf.decode(errors="replace").splitlines():
                        if "SETUP-FAILED" in l:
                            print("   ", l.strip())
                sys.exit(0)
    print("timed out waiting for the bridge; last output was:", file=sys.stderr)
    sys.stderr.write(buf.decode(errors="replace")[-500:] + "\n")
    sys.exit(1)
PY

echo "$PORT is now the project UART (no REPL until you press RUN)"
