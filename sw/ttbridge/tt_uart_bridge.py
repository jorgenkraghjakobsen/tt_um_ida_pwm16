"""
tt_uart_bridge - turn the Tiny Tapeout demo board into the project's USB serial port.

tt_um_ida_pwm16 puts its UART on ui[3] (RX) and uo[4] (TX), which is option 1 of
Tiny Tapeout's recommended UART pinout.  That is not an arbitrary choice: on the
demo board those two pins land on the RP2350's own hardware UART1 -

    ui[3]  = GPIO20 = UART1.tx    (RP2350 drives  -> project receives)
    uo[4]  = GPIO37 = UART1.rx    (RP2350 listens <- project transmits)

so the RP2350 can be the bridge itself.  No adapter, no wiring, no second board.

    host  <--USB CDC-->  RP2350  <--UART1-->  tt_um_ida_pwm16

Why this script also starts the project
---------------------------------------
mpremote enters the raw REPL, which skips main.py, so the SDK never runs and the
project is left unselected and unclocked.  (Symptom: the PWM pins go dead flat.)
So run() does the startup itself before bridging - probe the board, enable the
default project from config.ini, and start the clock.

Usage, from the host:

    mpremote connect /dev/ttyACM0 fs cp tt_uart_bridge.py :tt_uart_bridge.py
    mpremote connect /dev/ttyACM0 exec --no-follow \
        "import tt_uart_bridge; tt_uart_bridge.run()"

then wait for the READY sentinel and talk to /dev/ttyACM0 with ucom or pwmui.
sw/ttbridge/start_bridge.sh does all of that for you.

While the bridge runs there is NO REPL - the port carries raw binary in both
directions, and Ctrl-C is disabled so that a 0x03 data byte reaches the chip
instead of raising KeyboardInterrupt.  Press RUN on the demo board (or unplug
it) to get the REPL back.

There is deliberately no escape sequence.  The register protocol carries
arbitrary binary, so any magic byte pattern could also be real data, and a
bridge that silently ate one register write would be far more painful to debug
than pressing a button.
"""

import sys
import select
import micropython
from machine import UART, Pin

UART_ID = 1
TX_GPIO = 20      # -> ui[3]  project uart_rx
RX_GPIO = 37      # <- uo[4]  project uart_tx
BAUDRATE = 115200
CLOCK_HZ = 10_000_000

READY = "<<TT-UART-BRIDGE-READY>>"
FAILED = "<<TT-UART-BRIDGE-SETUP-FAILED>>"


def setup_board(clock_hz=CLOCK_HZ, project=None):
    """Do what main.py would have done: select the project and clock it."""
    from ttboard.boot.demoboard_detect import DemoboardDetect
    from ttboard.demoboard import DemoBoard

    DemoboardDetect.probe()
    tt = DemoBoard.get()
    if project:
        tt.shuttle.get(project).enable()
    else:
        tt.load_default_project()
    if clock_hz:
        tt.clock_project_PWM(clock_hz)
    return tt


def run(baudrate=BAUDRATE, clock_hz=CLOCK_HZ, project=None,
        uart_id=UART_ID, tx=TX_GPIO, rx=RX_GPIO, setup=True):
    """Pipe the USB CDC to the project UART until the board is reset."""
    tt = None
    if setup:
        try:
            tt = setup_board(clock_hz, project)
        except Exception as e:          # noqa: BLE001 - report and carry on
            print("%s %r" % (FAILED, e))

    # Claim GPIO20/37 for UART1.  Do this *after* the SDK setup, which drives
    # ui_in as plain outputs - creating the UART re-muxes the pin.
    uart = UART(
        uart_id,
        baudrate=baudrate,
        tx=Pin(tx),
        rx=Pin(rx),
        bits=8,
        parity=None,
        stop=1,
        timeout=0,
        rxbuf=1024,
        txbuf=1024,
    )

    # Tell the host the noisy part is over and the stream is now transparent.
    if tt is not None:
        print("%s clock=%s" % (READY, clock_hz))
    else:
        print("%s (no board setup)" % READY)

    # The register protocol is arbitrary binary: 0x03 has to reach the chip as
    # data, not be swallowed as a keyboard interrupt.
    micropython.kbd_intr(-1)

    poller = select.poll()
    poller.register(sys.stdin, select.POLLIN)
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    try:
        while True:
            # host -> project
            while poller.poll(0):
                b = stdin.read(1)
                if not b:
                    break
                uart.write(b)

            # project -> host
            n = uart.any()
            if n:
                stdout.write(uart.read(n))
    finally:
        micropython.kbd_intr(3)
