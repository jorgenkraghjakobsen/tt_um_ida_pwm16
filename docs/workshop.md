# IDA Embedded — open source chip design workshop

**Design:** `tt_um_ida_pwm16`, a 16 channel PWM / RC servo controller
**Target:** Tiny Tapeout IHP SG13G2, shuttle `ttihp26b`
**Why this design:** it is small enough to understand in an afternoon, big
enough to need real decisions (area, pin budget, clocking), and when it works a
row of servos physically waves at you.

---

## 0. What we are actually doing

The Sky130 shuttle closing 7 September is full, so we are aiming at the next
IHP run. Everything in this repo is already wired for that: the GitHub actions
build GDS with LibreLane against `ihp-sg13g2`, run the precheck, run the tests
on the gate level netlist, and build an ICE40UP5K bitstream for the Tiny Tapeout
FPGA board so people can hold the design in their hands long before the chip
comes back.

Three blocks, and the workshop follows them in order:

```
        ui[0] ──► ┌──────────┐  addr/data  ┌───────────────┐  16 x 8 bit ┌────────┐ ──► 15 pins
   uart_rx        │ uart_if  │ ──────────► │ rb_pwm16      │ ──────────► │ pwm16  │
        uo[0] ◄── │ protocol │ ◄────────── │ register bank │             │ engine │
   uart_tx        └──────────┘             └───────────────┘             └────────┘
             lab 3                    lab 2                        lab 1
```

## 1. Tools

```bash
# simulation and lint
sudo apt install iverilog verilator
pip install cocotb pytest

# synthesis / FPGA
#   yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader   (Tang Nano)
#   or just use the GitHub action for the TT FPGA board

# register map generator and the web UI
go version        # 1.21 or newer

# the command line register tool
git clone https://github.com/jorgenkraghjakobsen/ucom && cd ucom && make install
```

Check it all works:

```bash
make test      # 14 cocotb tests, about 70 seconds
make lint      # verilator -Wall, must be silent
make area      # area against the real IHP standard cells
```

---

## Lab 1 — the PWM engine, and why sharing matters

Open [`src/pwm16.v`](../src/pwm16.v).

A servo wants a 20 ms frame with a 1.0–2.0 ms pulse. The obvious design gives
every channel its own 13 bit counter. Sixteen of those is 208 flops just for
counting, before any position registers.

Instead there is **one** timebase and sixteen 8 bit comparators. The frame
counter runs 0…5119 ticks; during the first 256 ticks every channel is high,
during the next 256 it stays high while `frame_counter[7:0] < position`.

Things to try:

1. Run `make area`. Note the number.
2. Change `pwm16.v` to give each channel its own counter. Run `make area`
   again. How much did sixteen counters cost, and would the design still fit in
   2x2 tiles?
3. 5120 = 20 × 256 is not an accident. Work out what breaks in plain PWM mode
   if the frame were 5000 ticks instead.
4. The outputs are registered (`pwm_out <= …`). Remove the flop and look at the
   waveform in `test/tb.fst`. Why does a servo care?

## Lab 2 — the register map is the source of truth

Open [`regmap/register_bank.go`](../regmap/register_bank.go). One Go file
describes every register, and generates:

| Output | Used by |
|---|---|
| `rb_pwm16.v` | the chip |
| `reg_file_pwm16` | `ucom`, tab completion, `dblookup` |
| `reg_file_pwm16.json` | anything else |
| `regmap_pwm16.md` | the datasheet |

Things to try:

1. Add a register — say `ctrl.led_pattern` at `0x0C`. Run `make regs`. Watch it
   appear in the Verilog, in `ucom info` and in the tab completion, with no
   other edits.
2. Look at how `preset` works. `ctrl.center_all` is a *self clearing* strobe
   that pulses the `pwm_preset` input, which reloads every channel register with
   its reset value. "Reset all to 50 %" is one line of Go, not a special case in
   the RTL.
3. Try `go run register_bank.go -lang sv`. That is the original SystemVerilog
   struct flavour from `fpga_template`. Why did the ASIC need the flat Verilog
   version? (Hint: `yosys -m slang` is not in the LibreLane flow.)

## Lab 3 — the interface, and what silicon costs

Open [`src/uart_if.v`](../src/uart_if.v) and compare it with
`fpga_template/digital/uart_if/uart_if.v`.

The FPGA version has `reg [7:0] tx_queue [0:255]`. On an FPGA that is one block
RAM and costs nothing. On this chip it would be **2048 flip flops** — five
times the entire rest of the design. It had to go, replaced by streaming block
reads one byte at a time.

That is the single most useful lesson of the day: *the same RTL is not the same
cost in the two technologies.*

Things to try:

1. Add the queue back and run `make area`. Compare against the 2x2 tile budget.
2. The baud divider became a runtime input instead of a parameter. Why does that
   matter for a chip you cannot re-spin? Look at how `ui[2]` and the "zero means
   default" rule in `tt_um_ida_pwm16.v` work together.
3. Break the protocol on purpose: send `W` then only the address and stop. What
   happens? Look at the `P_IDLE` resync path.

## Lab 4 — pin budget

16 usable output pins, 16 channels, and the UART needs a transmitter. Work out
the options before reading how it was resolved (`ctrl.uart_tx_en` and the mux
on `uo[0]` in `tt_um_ida_pwm16.v`).

| | pins |
|---|---|
| `ui[7:0]` | inputs only |
| `uo[7:0]` | outputs |
| `uio[7:0]` | bidirectional, we drive all eight |

## Lab 5 — run it on real hardware

**Tiny Tapeout FPGA board (FabricFox):** push, let the `fpga` workflow run,
download the `fpga_bitstream` artifact, then

```bash
python tt/tt_fpga.py configure --upload --set-default --clockrate 10000000
```

**Tang Nano 9K:**

```bash
make fpga
cd fpga/tangnano && make load
```

Then, either board:

```bash
cd sw
./bringup.sh                 # pass/fail check of the whole register interface
ucom w pwm.ch3 0xC0          # move channel 3
cd pwmui && go run .         # sixteen sliders at http://localhost:8080
```

And with nothing plugged into the serial port at all: strap `ui[1]` high (S2 on
the Tang Nano) and every channel starts sweeping.

**Wiring servos:** signal from the pin, but **5 V and ground from a separate
supply**. Sixteen SG90s stalling will brown out any dev board. Tie the grounds.

## Lab 6 — tapeout

```bash
git push                       # the gds action does the rest
```

Watch the `gds` workflow: LibreLane hardens the design, the precheck runs the
DRC/LVS style rules Tiny Tapeout requires, the gate level test re-runs all 14
cocotb tests on the extracted netlist, and the viewer publishes a 3D layout to
GitHub Pages.

Then submit at <https://app.tinytapeout.com>.

Things to check in the run:

- the utilisation report — we predicted ~36 %, what did LibreLane get?
- the timing report — we asked for 50 MHz (`CLOCK_PERIOD: 20` in
  `src/config.json`) but plan to run at 10 MHz. How much slack is there?
- the gate level test — same tests, real netlist. Anything that passes at RTL
  and fails here is a real bug.
