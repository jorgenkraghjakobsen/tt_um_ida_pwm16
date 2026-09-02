# Tiny Tapeout FPGA board (FabricFox)

The `fpga` GitHub action builds an ICE40UP5K bitstream from the *same* RTL that
goes to silicon, wrapped in TinyTapeout's own `tt_fpga_top.v` and pinned with
their `tt_fpga_fabricfoxv2.pcf`. So the pinout you get on the FPGA board is
exactly the pinout the chip will have.

## Getting the bitstream

It comes out of CI as the `fpga_bitstream` artifact:

```bash
gh run download $(gh run list -w fpga -L1 --json databaseId -q '.[0].databaseId') -D /tmp/tt
cp /tmp/tt/fpga_bitstream/build/tt_um_ida_pwm16.bin fpga/ttfpga/
```

`tt_um_ida_pwm16.bin` in this directory is a build of the current commit.

## Loading it onto the demo board

```bash
python tt/tt_fpga.py configure --upload --set-default --clockrate 10000000
```

(`tt` is the tt-support-tools checkout — the devcontainer puts one in place, or
clone <https://github.com/TinyTapeout/tt-support-tools>.)

## Clock rate: use 10 MHz here

| | Fmax | at |
|---|---|---|
| ICE40UP5K (this board) | 27.7 MHz | 21 % of the LCs |
| Tang Nano 9K (GW1N-9C) | 96 MHz | |
| IHP sg13g2 (the chip) | LibreLane signs off at 50 MHz (`CLOCK_PERIOD: 20`) | |

The FPGA emulation is the slow one. **Run the demo board at 10 MHz** and leave
`ui[2]` low, which is what the built in divider defaults expect anyway. The
`ui[2] = 1` / 50 MHz strap is for the real chip; the UP5K will not close timing
there.

Everything else — `ucom`, `sw/bringup.sh`, the web UI — behaves identically
against the FPGA board and against the chip.
