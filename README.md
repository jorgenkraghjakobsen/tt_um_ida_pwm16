![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# tt_um_ida_pwm16 — 16 Channel PWM / Servo Controller

Workshop design for **IDA Embedded — open source chip design**, targeting the
Tiny Tapeout **IHP SG13G2** shuttle (`ttihp26b`).

Sixteen RC servos, one serial port, one chip. Read
[docs/info.md](docs/info.md) for the datasheet.

```
        ui[0] ──► ┌──────────┐  addr/data  ┌───────────────┐  16 x 8 bit ┌────────┐ ──► uo[7:1]  ch0..ch6
   uart_rx        │ uart_if  │ ──────────► │ rb_pwm16      │ ──────────► │ pwm16  │ ──► uio[7:0] ch7..ch14
        uo[0] ◄── │ protocol │ ◄────────── │ register bank │             │ engine │ ──► uo[0]    ch15*
   uart_tx        └──────────┘             └───────────────┘             └────────┘
```

| | |
|---|---|
| Channels | 16 (15 on dedicated pins, ch15 shares `uo[0]` with the UART TX) |
| Servo frame | 20 ms, pulse 1.000–1.996 ms, 8 bit position |
| PWM mode | duty / 256 at ~1 kHz, same registers |
| Interface | UART 115200 8N1, `W`/`R`/`B`/`b` register protocol |
| Clock | 10 MHz nominal, 50 MHz selectable on `ui[2]`, dividers are registers |
| Area | ~39.5 k µm² of sg13g2 cells, 398 flops → **2x2 tiles** at ~36 % utilisation |
| Standalone | strap `ui[1]` and it sweeps all 16 channels with no host |

## Layout

```
src/          the RTL that goes to silicon
  tt_um_ida_pwm16.v   TT top level, pin mapping, clock strapping
  uart_if.v           UART + register protocol   (from fpga_template, slimmed for ASIC)
  rb_pwm16.v          register bank              (generated, do not edit)
  pwm16.v             the 16 channel PWM engine
regmap/       register_bank.go and everything it generates
test/         cocotb testbench, 14 tests, runs on RTL and on the gate level netlist
fpga/tangnano Tang Nano 9K build of the exact same RTL
sw/           ucom bring up script and the Go web UI
```

## Where the parts came from

The UART and the register bank generator are lifted from
[`fpga_template`](https://github.com/jorgenkraghjakobsen/fpga_template), so the
protocol, the `.reg_file` format and the `ucom` tooling are unchanged. Three
things had to be added to make them tapeout ready — all of them useful beyond
this project:

1. **`uart_if.v`** dropped its 256 byte TX queue (2048 flops, more than the
   entire rest of the design) in favour of streaming block reads a byte at a
   time, and its baud divider became a runtime input instead of a parameter.
2. **`register_bank.go`** gained a **Verilog-2005 back end**. The SystemVerilog
   struct output needs yosys+slang; LibreLane and iverilog are far happier with
   flat Verilog, so the generator now flattens every symbol into a
   `<section>__<symbol>` port. `-lang sv` still emits the original flavour.
3. **`register_bank.go`** also gained two register behaviours: a per section
   **`preset`** input that reloads every register in a section with its reset
   value (that is `ctrl.center_all`, "everything back to 50 %"), and
   **self clearing** symbols for write-1-to-strobe bits.

## Build and test

```bash
make regs      # regenerate the register bank, reg file, JSON and markdown
make test      # cocotb, 14 tests, RTL
make lint      # verilator -Wall, clean
make area      # synthesise against the IHP cells and print the area
make fpga      # Tang Nano 9K bitstream
```

GDS, precheck, gate level tests and the ICE40UP5K bitstream for the **TT FPGA
board (FabricFox)** all come out of the GitHub actions in `.github/workflows`.
To put the FPGA build on the demo board:

```bash
# after the fpga workflow finishes, download the fpga_bitstream artifact, then
python tt/tt_fpga.py configure --upload --set-default --clockrate 10000000
```

## Pinout

| Pin | Function |
|-----|----------|
| `ui[0]` | UART RX, 115200 8N1 |
| `ui[1]` | DEMO — strap high to run the built in sweep |
| `ui[2]` | CLK_SEL — 0: 10 MHz defaults, 1: 50 MHz defaults |
| `ui[3]` | CENTER — rising edge centres all channels |
| `uo[0]` | UART TX, or PWM ch15 when `ctrl.uart_tx_en` is cleared |
| `uo[1..7]` | PWM ch0 … ch6 |
| `uio[0..7]` | PWM ch7 … ch14 (always outputs) |

## Licence

Apache-2.0, see [LICENSE](LICENSE).
