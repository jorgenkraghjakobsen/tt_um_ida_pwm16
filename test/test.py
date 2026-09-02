# Cocotb testbench for tt_um_ida_pwm16
#
# The design talks the fpga_template register protocol over UART, so the
# testbench contains a small bit-banged UART host.  Everything is timed in
# clock cycles, which keeps the same numbers valid for RTL and gate level.
#
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

# --- must match the DIV_*_A parameters in tt_um_ida_pwm16.v (ui[2] = 0) ------
CLK_HZ = 10_000_000
CLK_NS = 100                 # 10 MHz
BIT_CYCLES = 87              # 10 MHz / 115200
DEF_PWM_DIV = 39             # 10 MHz -> 3.9 us tick

# --- register map (see regmap/regmap_pwm16.md) ------------------------------
CTRL_CHIP_ID = 0x00
CTRL_VERSION = 0x01
CTRL_CFG = 0x02
CTRL_CENTER = 0x03
CTRL_DIV_COM_L = 0x04
CTRL_DIV_COM_H = 0x05
CTRL_DIV_PWM_L = 0x06
CTRL_DIV_PWM_H = 0x07
CTRL_CHAN_EN_L = 0x08
CTRL_CHAN_EN_H = 0x09
CTRL_SCRATCH = 0x0A
CTRL_STATUS = 0x0B
PWM_CH0 = 0x10

CFG_ENABLE = 1 << 0
CFG_SERVO = 1 << 1
CFG_UART_TX_EN = 1 << 2
CFG_DEMO = 1 << 3
CFG_INVERT = 1 << 4

FRAME_TICKS = 5120           # 20 ms in ticks


class UartHost:
    """Bit-banged 115200 8N1 host on ui_in[3] / uo_out[4]."""

    def __init__(self, dut, bit_cycles=BIT_CYCLES):
        self.dut = dut
        self.bit = bit_cycles

    def _set_rx(self, value):
        cur = int(self.dut.ui_in.value)
        self.dut.ui_in.value = (cur & 0xF7) | ((value & 1) << 3)

    async def send_byte(self, value):
        self._set_rx(0)                                  # start bit
        await ClockCycles(self.dut.clk, self.bit)
        for i in range(8):
            self._set_rx((value >> i) & 1)               # LSB first
            await ClockCycles(self.dut.clk, self.bit)
        self._set_rx(1)                                  # stop bit
        await ClockCycles(self.dut.clk, self.bit)

    async def send(self, data):
        for b in data:
            await self.send_byte(b)

    async def recv_byte(self, timeout_cycles=200000):
        """Wait for a start bit on uo_out[0] and shift in one byte."""
        waited = 0
        while (int(self.dut.uo_out.value) >> 4) & 1:
            await ClockCycles(self.dut.clk, 1)
            waited += 1
            assert waited < timeout_cycles, "timeout waiting for UART start bit"
        # we are somewhere inside the start bit, walk to the middle of bit 0
        await ClockCycles(self.dut.clk, self.bit + self.bit // 2)
        value = 0
        for i in range(8):
            value |= ((int(self.dut.uo_out.value) >> 4) & 1) << i
            await ClockCycles(self.dut.clk, self.bit)
        return value

    async def recv(self, count):
        return [await self.recv_byte() for _ in range(count)]

    # --- register level ----------------------------------------------------
    async def write(self, addr, value):
        await self.send([ord('W'), addr & 0xFF, value & 0xFF])
        await ClockCycles(self.dut.clk, 20)

    async def read(self, addr):
        await self.send([ord('R'), addr & 0xFF])
        return await self.recv_byte()

    async def write_block(self, addr, values):
        await self.send([ord('B'), addr & 0xFF, len(values)] + list(values))
        await ClockCycles(self.dut.clk, 20)

    async def read_block(self, addr, count):
        await self.send([ord('b'), addr & 0xFF, count])
        return await self.recv(count)


async def start_dut(dut, ui_extra=0):
    """Clock, reset, and a UART host.  ui_extra sets the strap pins."""
    clock = Clock(dut.clk, CLK_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0x08 | ui_extra          # uart_rx (ui[3]) idles high
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    return UartHost(dut)


def pins(dut):
    """Return the 16 channel values as seen on the pins, ch0 .. ch15.

    ch0..ch3  -> uo_out[3:0]
    ch4..ch6  -> uo_out[7:5]
    ch7..ch14 -> uio_out[7:0]
    ch15      -> uo_out[4]   (only meaningful when ctrl.uart_tx_en = 0)
    """
    uo = int(dut.uo_out.value)
    uio = int(dut.uio_out.value)
    out = [(uo >> i) & 1 for i in range(4)]
    out += [(uo >> (5 + i)) & 1 for i in range(3)]
    out += [(uio >> i) & 1 for i in range(8)]
    out += [(uo >> 4) & 1]
    return out


async def measure_high(dut, channel, div, timeout_frames=3):
    """Measure the high time of one channel in ticks, over one frame."""
    frame_cycles = FRAME_TICKS * div
    # wait for a low period so we start from a known place
    limit = frame_cycles * timeout_frames
    n = 0
    while pins(dut)[channel] == 1:
        await ClockCycles(dut.clk, 1)
        n += 1
        assert n < limit, "channel never went low"
    while pins(dut)[channel] == 0:
        await ClockCycles(dut.clk, 1)
        n += 1
        assert n < limit, "channel never went high"
    high = 0
    while pins(dut)[channel] == 1:
        await ClockCycles(dut.clk, 1)
        high += 1
        assert high < limit, "channel never went low again"
    return high / div          # in ticks


# =============================================================================
# Tests
# =============================================================================

@cocotb.test()
async def test_link_and_scratch(dut):
    """Chip id, version and a scratch register round trip."""
    dut._log.info("UART link check")
    uart = await start_dut(dut)

    chip_id = await uart.read(CTRL_CHIP_ID)
    assert chip_id == 0x16, f"chip_id was 0x{chip_id:02x}, expected 0x16"

    version = await uart.read(CTRL_VERSION)
    assert version == 0x01, f"version was 0x{version:02x}"

    for pattern in (0x00, 0xA5, 0x5A, 0xFF):
        await uart.write(CTRL_SCRATCH, pattern)
        got = await uart.read(CTRL_SCRATCH)
        assert got == pattern, f"scratch: wrote 0x{pattern:02x} read 0x{got:02x}"

    dut._log.info("link OK")


@cocotb.test()
async def test_reset_values(dut):
    """Everything comes out of reset centred and running."""
    uart = await start_dut(dut)

    cfg = await uart.read(CTRL_CFG)
    assert cfg & CFG_ENABLE, "enable should be set out of reset"
    assert cfg & CFG_SERVO, "servo_mode should be set out of reset"
    assert cfg & CFG_UART_TX_EN, "uart_tx_en should be set out of reset"

    assert await uart.read(CTRL_CHAN_EN_L) == 0xFF
    assert await uart.read(CTRL_CHAN_EN_H) == 0xFF
    assert await uart.read(CTRL_DIV_COM_L) == 0x00
    assert await uart.read(CTRL_DIV_PWM_L) == 0x00

    for ch in range(16):
        val = await uart.read(PWM_CH0 + ch)
        assert val == 0x80, f"ch{ch} reset to 0x{val:02x}, expected 0x80"


@cocotb.test()
async def test_block_access(dut):
    """Block write and block read across the whole channel section."""
    uart = await start_dut(dut)

    values = [(0x10 + 3 * i) & 0xFF for i in range(16)]
    await uart.write_block(PWM_CH0, values)
    got = await uart.read_block(PWM_CH0, 16)
    assert got == values, f"block readback {got} != {values}"

    # single reads must agree with the block read
    for ch in (0, 7, 15):
        one = await uart.read(PWM_CH0 + ch)
        assert one == values[ch], f"ch{ch}: single 0x{one:02x} block 0x{values[ch]:02x}"


@cocotb.test()
async def test_center_all(dut):
    """ctrl.center_all is a self clearing strobe that presets the section."""
    uart = await start_dut(dut)

    await uart.write_block(PWM_CH0, [i * 7 & 0xFF for i in range(16)])
    assert await uart.read(PWM_CH0) == 0x00
    assert await uart.read(PWM_CH0 + 3) == 0x15

    await uart.write(CTRL_CENTER, 0x01)
    for ch in range(16):
        val = await uart.read(PWM_CH0 + ch)
        assert val == 0x80, f"ch{ch} after center_all is 0x{val:02x}"

    # the strobe itself always reads back zero
    assert await uart.read(CTRL_CENTER) == 0x00

    # and the control section survived untouched
    assert await uart.read(CTRL_CHAN_EN_L) == 0xFF


@cocotb.test()
async def test_center_pin(dut):
    """A rising edge on ui[1] centres every channel with no host involved."""
    uart = await start_dut(dut)

    await uart.write_block(PWM_CH0, [0x20] * 16)
    assert await uart.read(PWM_CH0 + 5) == 0x20

    ui = int(dut.ui_in.value)
    dut.ui_in.value = ui | (1 << 1)
    await ClockCycles(dut.clk, 20)
    dut.ui_in.value = ui
    await ClockCycles(dut.clk, 20)

    for ch in (0, 5, 15):
        val = await uart.read(PWM_CH0 + ch)
        assert val == 0x80, f"ch{ch} after centre pin is 0x{val:02x}"


@cocotb.test()
async def test_pin_mapping(dut):
    """Every channel register drives exactly the pin the datasheet claims.

    In plain PWM mode with a one clock tick, channel n is high for exactly
    `duty[n]` of every 256 ticks.  Give all 16 channels a different duty, count
    the highs on each pin over one period, and the counts come back as the
    register values - which only works if the pin mapping is right.
    """
    uart = await start_dut(dut)

    duties = [16 * i + 8 for i in range(16)]        # 8, 24, ... 248
    await uart.write(CTRL_DIV_PWM_L, 1)
    await uart.write_block(PWM_CH0, duties)
    # servo_mode = 0 and uart_tx_en = 0, so uo[4] carries ch15.  No more reads
    # after this point, the transmitter is disconnected from the pin.
    await uart.write(CTRL_CFG, CFG_ENABLE)
    await ClockCycles(dut.clk, 300)

    counts = [0] * 16
    for _ in range(256):
        state = pins(dut)
        for ch in range(16):
            counts[ch] += state[ch]
        await ClockCycles(dut.clk, 1)

    for ch in range(16):
        assert counts[ch] == duties[ch], (
            f"ch{ch}: pin was high {counts[ch]}/256 ticks, "
            f"register says {duties[ch]} - pin mapping or duty is wrong")
    dut._log.info(f"all 16 channels map correctly: {counts}")


@cocotb.test()
async def test_uart_tx_en_keeps_uo4_serial(dut):
    """While ctrl.uart_tx_en is set, uo[4] is the UART and never the PWM."""
    uart = await start_dut(dut)

    await uart.write(CTRL_DIV_PWM_L, 1)
    await uart.write_block(PWM_CH0, [0x00] * 15 + [0xFF])   # ch15 hard on
    await uart.write(CTRL_CFG, CFG_ENABLE | CFG_UART_TX_EN)
    await ClockCycles(dut.clk, 300)

    for _ in range(600):                                    # idle UART = high
        assert (int(dut.uo_out.value) >> 4) & 1 == 1, "uo[4] left the UART idle state"
        await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_servo_timing(dut):
    """Servo pulse width is 1 ms + position, frame is 20 ms."""
    div = 2
    uart = await start_dut(dut)
    await uart.write(CTRL_DIV_PWM_L, div)

    for ch, value, expect in ((0, 0x00, 256), (3, 0x80, 384), (10, 0xFF, 511)):
        await uart.write(PWM_CH0 + ch, value)
        await ClockCycles(dut.clk, 50)
        high = await measure_high(dut, ch, div)
        # +-1 tick for the output register pipeline
        assert abs(high - expect) <= 1, (
            f"ch{ch} value 0x{value:02x}: {high} ticks high, expected {expect}")
        dut._log.info(f"ch{ch} 0x{value:02x} -> {high} ticks "
                      f"({high * 1000.0 / 256:.0f} us at a 3.9 us tick)")

    # frame period: measure two consecutive rising edges on ch0
    await uart.write(PWM_CH0, 0x00)
    await ClockCycles(dut.clk, 50)
    while pins(dut)[0] == 1:
        await ClockCycles(dut.clk, 1)
    while pins(dut)[0] == 0:
        await ClockCycles(dut.clk, 1)
    period = 0
    while pins(dut)[0] == 1:
        await ClockCycles(dut.clk, 1)
        period += 1
    while pins(dut)[0] == 0:
        await ClockCycles(dut.clk, 1)
        period += 1
    assert abs(period / div - FRAME_TICKS) <= 2, (
        f"frame is {period / div} ticks, expected {FRAME_TICKS}")


@cocotb.test()
async def test_default_tick_rate(dut):
    """With the divider register at 0 the built in 10 MHz default is used.

    A channel at 0x00 in servo mode is high for exactly the first millisecond,
    so the high time proves the tick rate without simulating a whole frame.
    """
    uart = await start_dut(dut)
    await uart.write(PWM_CH0, 0x00)
    await ClockCycles(dut.clk, 50)

    high = await measure_high(dut, 0, DEF_PWM_DIV)     # in ticks
    assert abs(high - 256) <= 1, (
        f"1 ms pulse was {high} ticks, expected 256 - the built in "
        f"divider default is not {DEF_PWM_DIV} clocks")
    us = high * DEF_PWM_DIV * 1e6 / CLK_HZ
    dut._log.info(f"default tick: 1 ms pulse = {high} ticks = {us:.1f} us")


@cocotb.test()
async def test_pwm_mode(dut):
    """Plain PWM mode: duty = value / 256, period = 256 ticks."""
    div = 2
    uart = await start_dut(dut)
    await uart.write(CTRL_DIV_PWM_L, div)
    await uart.write(CTRL_CFG, CFG_ENABLE | CFG_UART_TX_EN)   # servo_mode = 0

    for ch, value in ((1, 0x40), (5, 0xC0)):
        await uart.write(PWM_CH0 + ch, value)
        await ClockCycles(dut.clk, 50)
        high = await measure_high(dut, ch, div)
        assert abs(high - value) <= 1, (
            f"ch{ch} duty 0x{value:02x}: {high} ticks high")


@cocotb.test()
async def test_enable_and_chan_en(dut):
    """Global enable and per channel enable both park outputs low."""
    uart = await start_dut(dut)
    await uart.write(CTRL_DIV_PWM_L, 1)
    # plain PWM so one period is 256 clocks and a short window sees everything
    await uart.write(CTRL_CFG, CFG_ENABLE | CFG_UART_TX_EN)

    # disable channels 0..7, leave 8..15 running
    await uart.write(CTRL_CHAN_EN_L, 0x00)
    await ClockCycles(dut.clk, 300)
    seen = [0] * 16
    for _ in range(300):
        state = pins(dut)
        for ch in range(16):
            seen[ch] |= state[ch]
        await ClockCycles(dut.clk, 1)
    assert sum(seen[0:7]) == 0, "channels 0..6 should be parked low"
    assert sum(seen[8:15]) > 0, "channels 8..14 should still be pulsing"

    # global disable kills everything
    await uart.write(CTRL_CHAN_EN_L, 0xFF)
    await uart.write(CTRL_CFG, CFG_UART_TX_EN)                # enable = 0
    await ClockCycles(dut.clk, 300)
    seen = [0] * 16
    for _ in range(300):
        state = pins(dut)
        for ch in range(15):
            seen[ch] |= state[ch]
        await ClockCycles(dut.clk, 1)
    assert sum(seen[0:15]) == 0, "global enable = 0 should park every channel"


@cocotb.test()
async def test_invert(dut):
    """ctrl.invert flips every output pin."""
    uart = await start_dut(dut)
    await uart.write(CTRL_DIV_PWM_L, 1)
    await uart.write(CTRL_CFG, CFG_UART_TX_EN | CFG_INVERT)   # enable = 0
    await ClockCycles(dut.clk, 300)
    state = pins(dut)
    assert all(state[ch] == 1 for ch in range(15)), (
        "parked + inverted should idle high")


@cocotb.test()
async def test_demo_pin(dut):
    """ui[0] runs the sweep generator with no host traffic at all."""
    uart = await start_dut(dut)
    await uart.write(CTRL_DIV_PWM_L, 1)

    ui = int(dut.ui_in.value)
    dut.ui_in.value = ui | (1 << 0)
    await ClockCycles(dut.clk, 50)

    status = await uart.read(CTRL_STATUS)
    assert status & 0x01, "ctrl.pin_demo should read the ui[0] strap"

    # even and odd channels mirror each other, so they cannot be equal
    w0 = await measure_high(dut, 0, 1)
    w1 = await measure_high(dut, 1, 1)
    assert w0 != w1, "demo sweep should mirror odd channels against even ones"
    assert 250 < w0 < 520, f"demo pulse out of servo range: {w0} ticks"
    assert 250 < w1 < 520, f"demo pulse out of servo range: {w1} ticks"


@cocotb.test()
async def test_runtime_baud_change(dut):
    """The UART divider is a register, so the link rate can be retuned."""
    uart = await start_dut(dut)

    new_div = 40
    await uart.write(CTRL_DIV_COM_L, new_div)
    await uart.write(CTRL_DIV_COM_H, 0)
    await ClockCycles(dut.clk, 200)

    fast = UartHost(dut, bit_cycles=new_div)
    chip_id = await fast.read(CTRL_CHIP_ID)
    assert chip_id == 0x16, f"chip_id at the new baud rate was 0x{chip_id:02x}"

    await fast.write(CTRL_SCRATCH, 0x3C)
    assert await fast.read(CTRL_SCRATCH) == 0x3C
