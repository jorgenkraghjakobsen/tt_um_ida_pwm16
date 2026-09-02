# Talking to the chip

Everything here speaks the same four byte-oriented commands that
[`src/uart_if.v`](../src/uart_if.v) implements:

| Operation    | On the wire                           | Answer            |
|--------------|---------------------------------------|-------------------|
| Single write | `'W' + addr + data`                   | none              |
| Single read  | `'R' + addr`                          | `data`            |
| Block write  | `'B' + addr + len + data0 + data1 ...` | none             |
| Block read   | `'b' + addr + len`                    | `data0 + data1 …` |

115200 8N1 by default, on `ui[3]` (RX) and `uo[4]` (TX) - option 1 of Tiny
Tapeout's [recommended UART pinout](https://tinytapeout.com/specs/pinouts/),
which lands on the demo board RP2350's hardware UART1 in both directions.

## Getting a serial port to the chip

The design's UART is on `ui[3]` (RX) and `uo[4]` (TX) at 3.3 V. You need
something that turns those two pins into a USB serial port.

### Option A - the TT demo board itself (no wiring at all)

`ui[3]`/`uo[4]` land on the demo board RP2350's hardware UART1 (GPIO20/GPIO37),
so the board can be its own bridge:

```bash
sw/ttbridge/start_bridge.sh /dev/ttyACM0 10000000
ucom -p /dev/ttyACM0 r ctrl.chip_id      # -> 0x16
```

`start_bridge.sh` copies `tt_uart_bridge.py` onto the board and starts it
detached, then waits for a `<<TT-UART-BRIDGE-READY>>` sentinel so the SDK's boot
banner is drained out of the CDC buffer before anything talks registers.

The script does the SDK startup itself - probe, enable the default project, start
the clock - because `mpremote` enters the raw REPL, which skips `main.py`. Skip
that and the project sits unselected and unclocked, with every PWM pin flat.

While the bridge runs there is no REPL on that port. **Press RUN on the demo
board to get it back.**

### Option B - an RP2040/RP2350 board as a USB-UART bridge

Any Pico-class board works. Flash Raspberry Pi's `debugprobe` firmware and it
enumerates as a clean USB CDC serial port, no code to write:

1. Grab the UF2 for your chip - `debugprobe_on_pico2.uf2` for RP2350 (Pico 2,
   Waveshare RP2350-Zero, ...), `debugprobe_on_pico.uf2` for RP2040 - from
   <https://github.com/raspberrypi/debugprobe/releases>.
2. Hold **BOOT** while plugging in the USB-C cable. The `RPI-RP2` drive appears.
3. Copy the UF2 onto it. The board reboots as
   `Raspberry Pi Debugprobe on Pico (CMSIS-DAP)`.

Wiring - the firmware puts the bridge on GP4/GP5:

| RP2350-Zero | direction | design pin |
|-------------|-----------|------------|
| `GP4` UART TX | ──► | `ui[3]` uart_rx |
| `GP5` UART RX | ◄── | `uo[4]` uart_tx |
| `GND` | ─── | `GND` |

Leave `5V` and `3V3` disconnected - the target powers itself. The ground wire
is not optional.

### Option C - any USB-serial adapter

An FTDI/CP210x/CH340 cable on the same two pins plus ground. Same thing, fewer
steps, if you have one spare.

### How the tools find the port

Out of the box the demo board's `/dev/ttyACM0` is the RP2350's MicroPython
REPL, and writing register bytes into a REPL just confuses it. But once
`tt_uart_bridge.py` is running, that *same* device node is the project UART -
the USB descriptor is identical either way.

So `pwmui` does not trust USB metadata. It ranks the ports (a debugprobe first,
then a plain USB-serial adapter, then anything that might be a bridged
MicroPython board) and then **asks each one for `ctrl.chip_id`**, keeping the
first that answers `0x16`. Ports that are obviously something else, like a
cellular modem, are never even poked. If nothing answers it says exactly what
it tried:

```
no chip yet (no port answered with chip_id 0x16: /dev/ttyACM0 did not answer;
/dev/ttyUSB0 skipped (cellular modem))
retrying every 3s - start the bridge and it will pick it up
```

and it keeps retrying, so you can leave the UI running and bring the bridge up
afterwards.

## ucom, the command line

[`ucom`](https://github.com/jorgenkraghjakobsen/ucom) finds `.reg_file_pwm16`
in this directory (a symlink to the file the register map generator writes), so
register names and tab completion work out of the box:

```bash
cd sw
ucom info                      # print the whole register map
ucom r ctrl.chip_id            # -> 0x16
ucom w pwm.ch3 0xC0            # channel 3 to about 1.75 ms
ucom r 0x10 16                 # block read all sixteen channels
ucom w ctrl.center_all 1       # everything back to 1.5 ms
ucom t pwm.ch0                 # interactive trim, arrow keys move the servo
```

`./bringup.sh` runs the whole sequence as a pass/fail check. Run it first on
the FPGA build, then again on the chip - the output should be identical.

## pwmui, the web front end

```bash
cd sw/pwmui
go run .                       # auto detect the port, serve http://localhost:8080
go run . -port /dev/ttyACM1
go run . -demo                 # no hardware, just look at the UI
```

Auto detect ranks ports by what they actually are, reading the USB product
string out of `/dev/serial/by-id`: a debugprobe bridge wins, a plain USB-serial
adapter is next, and a MicroPython REPL or a cellular modem is never chosen on
its own.

Sixteen sliders with a live microsecond readout, the mode bits as buttons, a
centre-all button and a host driven sine wave across all sixteen channels.
Dragging one slider is a single `W`; the presets and the wave push all sixteen
in one block write, 19 bytes, so the servos move together.
