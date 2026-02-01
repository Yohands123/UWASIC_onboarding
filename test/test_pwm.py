# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles, with_timeout
from cocotb.utils import get_sim_time


# ----------------------------
# Time helpers
# ----------------------------
def now_ns() -> float:
    return float(get_sim_time(units="ns"))


def freq_hz_from_period_ns(period_ns: float) -> float:
    return 1.0 / (period_ns * 1e-9)


# ----------------------------
# SPI helpers (copied from your test.py style)
# ----------------------------
async def await_half_sclk(dut):
    """Wait ~5us (half of 10us SCLK period) using dut.clk cycles."""
    start_time = get_sim_time(units="ns")
    while True:
        await ClockCycles(dut.clk, 1)
        if (start_time + 100 * 100 * 0.5) < get_sim_time(units="ns"):
            break


def ui_in_logicarray(ncs, bit, sclk):
    """ui_in[2]=nCS, ui_in[1]=COPI, ui_in[0]=SCLK"""
    return cocotb.types.LogicArray(f"00000{ncs}{bit}{sclk}")


async def send_spi_transaction(dut, r_w, address, data):
    """
    Send 16-bit SPI frame (mode 0), MSB-first:
      [15]=R/W, [14:8]=addr, [7:0]=data
    """
    data_int = int(data)

    first_byte = (int(r_w) << 7) | int(address)

    # Start transaction - CS low
    sclk = 0
    ncs = 0
    bit = 0
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
    await ClockCycles(dut.clk, 1)

    # Send first byte (RW + Address)
    for i in range(8):
        bit = (first_byte >> (7 - i)) & 0x1

        sclk = 0
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

        sclk = 1
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

    # Send second byte (Data)
    for i in range(8):
        bit = (data_int >> (7 - i)) & 0x1

        sclk = 0
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

        sclk = 1
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

    # End transaction - CS high
    sclk = 0
    ncs = 1
    bit = 0
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)

    # allow CDC + commit-on-nCS-rise
    await ClockCycles(dut.clk, 600)


async def spi_write(dut, addr: int, data: int):
    """Write-only SPI transaction."""
    await send_spi_transaction(dut, 1, addr, data)


# ----------------------------
# DUT setup
# ----------------------------
async def setup_dut(dut):
    # 10 MHz clock
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.uio_in.value = 0

    # idle SPI pins: nCS=1, COPI=0, SCLK=0
    dut.ui_in.value = ui_in_logicarray(1, 0, 0)

    # reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)


# ----------------------------
# PWM configuration
# ----------------------------
async def enable_pwm_on_uo0(dut):
    """
    Enable uo_out[0] and PWM mode on uo_out[0].
    """
    await spi_write(dut, 0x00, 0x01)  # out enable bit0
    await spi_write(dut, 0x02, 0x01)  # pwm enable bit0


# ----------------------------
# Measurement helpers
# ----------------------------
async def measure_period_and_high_time(sig, timeout_us=5000):
    """
    Measure:
      period = time between two rising edges
      high_time = time from rising to falling
    Returns (period_ns, high_time_ns)
    """
    await with_timeout(RisingEdge(sig), timeout_us, "us")
    t_rise1 = now_ns()

    await with_timeout(FallingEdge(sig), timeout_us, "us")
    t_fall = now_ns()

    await with_timeout(RisingEdge(sig), timeout_us, "us")
    t_rise2 = now_ns()

    return (t_rise2 - t_rise1), (t_fall - t_rise1)


async def assert_stays_constant(sig, expected: int, duration_us=2000, sample_step_us=50):
    steps = int(duration_us / sample_step_us)
    for _ in range(steps):
        assert int(sig.value) == expected, f"Signal changed: expected {expected}, got {int(sig.value)}"
        await Timer(sample_step_us, "us")


# ----------------------------
# TESTS
# ----------------------------
@cocotb.test()
async def test_pwm_0_percent(dut):
    await setup_dut(dut)
    await enable_pwm_on_uo0(dut)

    await spi_write(dut, 0x04, 0x00)  # 0%
    await ClockCycles(dut.clk, 2000)

    await assert_stays_constant(dut.uo_out[0], expected=0, duration_us=2000)


@cocotb.test()
async def test_pwm_100_percent(dut):
    await setup_dut(dut)
    await enable_pwm_on_uo0(dut)

    await spi_write(dut, 0x04, 0xFF)  # 100% special case
    await ClockCycles(dut.clk, 2000)

    await assert_stays_constant(dut.uo_out[0], expected=1, duration_us=2000)


@cocotb.test()
async def test_pwm_50_percent_and_frequency(dut):
    await setup_dut(dut)
    await enable_pwm_on_uo0(dut)

    await spi_write(dut, 0x04, 0x80)  # ~50%
    await ClockCycles(dut.clk, 2000)

    period_ns, high_ns = await measure_period_and_high_time(dut.uo_out[0], timeout_us=5000)

    f = freq_hz_from_period_ns(period_ns)
    duty = high_ns / period_ns

    dut._log.info(f"Measured period_ns={period_ns:.1f}, freq={f:.2f} Hz, duty={duty*100:.2f}%")

    # Frequency tolerance: 3000 +/- 1% => 2970..3030
    assert 2970.0 <= f <= 3030.0, f"PWM frequency out of range: {f:.2f} Hz"

    # Duty tolerance: +/-1% absolute
    expected_duty = 128 / 256
    assert abs(duty - expected_duty) <= 0.01, f"Duty out of range: got {duty:.4f}, expected {expected_duty:.4f}"
