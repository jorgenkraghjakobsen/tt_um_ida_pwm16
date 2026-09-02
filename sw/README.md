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
go run . -port /dev/ttyUSB1
go run . -demo                 # no hardware, just look at the UI
```

Sixteen sliders with a live microsecond readout, the mode bits as buttons, a
centre-all button and a host driven sine wave across all sixteen channels.
Dragging one slider is a single `W`; the presets and the wave push all sixteen
in one block write, 19 bytes, so the servos move together.
