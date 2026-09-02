# Tests

14 cocotb tests, run against the RTL and again against the gate level netlist.

```bash
make            # RTL
make GATES=yes  # gate level, needs gate_level_netlist.v from the gds action
```

The testbench contains a bit-banged UART host (`UartHost` in `test.py`) that
speaks the same `W`/`R`/`B`/`b` protocol as `ucom`, so a test reads almost the
same as a shell session against the real chip.

Everything is timed in **clock cycles**, not nanoseconds, so the same numbers
hold at RTL and at the gate level.

| Test | What it proves |
|---|---|
| `test_link_and_scratch` | `ctrl.chip_id` reads 0x16, and a scratch byte round trips |
| `test_reset_values` | every channel comes out of reset at 0x80, mode bits are sane |
| `test_block_access` | `B`/`b` across the whole 16 byte channel section |
| `test_center_all` | the self clearing strobe presets the section and reads back 0 |
| `test_center_pin` | a rising edge on `ui[3]` does the same with no host |
| `test_pin_mapping` | all 16 channels land on the right pin, checked in one 256 tick pass |
| `test_uart_tx_en_keeps_uo0_serial` | `uo[0]` stays the UART while `ctrl.uart_tx_en` is set |
| `test_servo_timing` | 1 ms + position pulse width, 20 ms frame |
| `test_default_tick_rate` | the built in 10 MHz divider default really is 39 clocks |
| `test_pwm_mode` | plain PWM duty = value / 256 |
| `test_enable_and_chan_en` | global and per channel enables park outputs low |
| `test_invert` | `ctrl.invert` flips every pin |
| `test_demo_pin` | `ui[0]` sweeps, odd channels mirror even ones |
| `test_runtime_baud_change` | the link survives being re-tuned to a new divider |

If a test passes at RTL and fails at the gate level, that is a real bug, not a
testbench problem — start with the reset and the clock.
