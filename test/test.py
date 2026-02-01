# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer, with_timeout
from cocotb.types import LogicArray
from cocotb.utils import get_sim_time


# ----------------------------
# SPI bit-bang helpers (Mode 0)
# ----------------------------
async def await_half_sclk(dut):
    """Wait ~5us (half of 10us SCLK period) using dut.clk cycles."""
    start_time = get_sim_time(units="ns")
    while True:
        await ClockCycles(dut.clk, 1)
        if (start_time + 100 * 100 * 0.5) < get_sim_time(units="ns"):
            break


def ui_in_logicarray(ncs, bit, sclk):
    """
    ui_in mapping:
      ui_in[2] = nCS
      ui_in[1] = COPI
      ui_in[0] = SCLK
    """
    return LogicArray(f"00000{ncs}{bit}{sclk}")


async def send_spi_transaction(dut, r_w, address, data):
    """
    Send 16-bit SPI frame (mode 0), MSB-first:
      [15]=R/W, [14:8]=addr, [7:0]=data

    DUT samples COPI on SCLK rising edges while nCS is low.
    """
    data_int = int(data) if isinstance(data, LogicArray) else int(data)

    if address < 0 or address > 127:
        raise ValueError("Address must be 7-bit (0-127)")
    if data_int < 0 or data_int > 255:
        raise ValueError("Data must be 8-bit (0-255)")

    first_byte = (int(r_w) << 7) | int(address)

    # Start transaction: nCS low
    sclk = 0
    ncs = 0
    bit = 0
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
    await ClockCycles(dut.clk, 1)

    # Byte 0: RW + address (MSB first)
    for i in range(8):
        bit = (first_byte >> (7 - i)) & 0x1

        sclk = 0
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

        sclk = 1
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

    # Byte 1: data (MSB first)
    for i in range(8):
        bit = (data_int >> (7 - i)) & 0x1

        sclk = 0
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

        sclk = 1
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)

    # End transaction: nCS high (commit happens on this edge in the DUT)
    sclk = 0
    ncs = 1
    bit = 0
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)

    # Give time for CDC + commit logic
    await ClockCycles(dut.clk, 600)


# ----------------------------
# Common setup
# ----------------------------
async def setup_dut(dut):
    dut._log.info("Setup clock + reset")

    # 10 MHz clock (100 ns period)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.uio_in.value = 0  # unused (all uio are outputs)

    # idle SPI pins: nCS=1, COPI=0, SCLK=0
    dut.ui_in.value = ui_in_logicarray(1, 0, 0)

    # reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)


# ----------------------------
# Measurement helpers
# ----------------------------
def now_ns():
    return float(get_sim_time(units="ns"))


def freq_hz(period_ns):
    return 1.0 / (period_ns * 1e-9)


async def wait_stable_value(sig, expected, duration_us=2000, step_us=20):
    """Assert signal stays constant for a window (good for 0% and 100% duty)."""
    steps = int(duration_us / step_us)
    for _ in range(steps):
        assert int(sig.value) == expected, f"Expected constant {expected}, got {int(sig.value)}"
        await Timer(step_us, "us")


async def measure_period_and_high(sig, timeout_us=5000):
    """
    Measures one PWM period using:
      rising -> falling -> rising
    Returns (period_ns, high_ns).
    """
    await with_timeout(RisingEdge(sig), timeout_us, "us")
    t1 = now_ns()

    await with_timeout(FallingEdge(sig), timeout_us, "us")
    tf = now_ns()

    await with_timeout(RisingEdge(sig), timeout_us, "us")
    t2 = now_ns()

    return (t2 - t1), (tf - t1)


async def enable_pwm_on_uo0(dut):
    """Enable uo_out[0] output + PWM mode on uo_out[0]."""
    await send_spi_transaction(dut, 1, 0x00, 0x01)  # out enable bit0
    await send_spi_transaction(dut, 1, 0x02, 0x01)  # pwm enable bit0


# ----------------------------
# TESTS
# ----------------------------
@cocotb.test()
async def test_spi(dut):
    await setup_dut(dut)

    dut._log.info("Write transaction, address 0x00, data 0xF0")
    await send_spi_transaction(dut, 1, 0x00, 0xF0)
    assert int(dut.uo_out.value) == 0xF0, f"Expected 0xF0, got {int(dut.uo_out.value)}"
    await ClockCycles(dut.clk, 200)

    dut._log.info("Write transaction, address 0x01, data 0xCC")
    await send_spi_transaction(dut, 1, 0x01, 0xCC)
    assert int(dut.uio_out.value) == 0xCC, f"Expected 0xCC, got {int(dut.uio_out.value)}"
    await ClockCycles(dut.clk, 200)

    dut._log.info("Write transaction, address 0x30 (invalid), data 0xAA")
    await send_spi_transaction(dut, 1, 0x30, 0xAA)
    await ClockCycles(dut.clk, 200)

    dut._log.info("Read transaction (ignored), address 0x00, data 0xBE")
    await send_spi_transaction(dut, 0, 0x00, 0xBE)
    assert int(dut.uo_out.value) == 0xF0, f"Expected 0xF0, got {int(dut.uo_out.value)}"
    await ClockCycles(dut.clk, 200)

    dut._log.info("SPI test completed successfully")


@cocotb.test()
async def test_pwm_freq(dut):
    """
    Verify PWM frequency ~ 3kHz (+/-1%) on uo_out[0] when enabled.
    Use duty=0x80 so it toggles.
    """
    await setup_dut(dut)
    await enable_pwm_on_uo0(dut)

    await send_spi_transaction(dut, 1, 0x04, 0x80)
    await ClockCycles(dut.clk, 2000)  # settle

    period_ns, _high_ns = await measure_period_and_high(dut.uo_out[0], timeout_us=5000)
    f = freq_hz(period_ns)

    dut._log.info(f"Measured period_ns={period_ns:.1f} => freq={f:.2f} Hz")
    assert 2970.0 <= f <= 3030.0, f"PWM frequency out of range: {f:.2f} Hz"


@cocotb.test()
async def test_pwm_duty(dut):
    """
    Verify duty for:
      - 0x00 (always low)
      - 0xFF (always high)
      - 0x80 (~50%)
    """
    await setup_dut(dut)
    await enable_pwm_on_uo0(dut)

    # --- 0% duty ---
    await send_spi_transaction(dut, 1, 0x04, 0x00)
    await ClockCycles(dut.clk, 2000)
    await wait_stable_value(dut.uo_out[0], expected=0, duration_us=2000)

    # --- 100% duty (special case) ---
    await send_spi_transaction(dut, 1, 0x04, 0xFF)
    await ClockCycles(dut.clk, 2000)
    await wait_stable_value(dut.uo_out[0], expected=1, duration_us=2000)

    # --- ~50% duty ---
    await send_spi_transaction(dut, 1, 0x04, 0x80)
    await ClockCycles(dut.clk, 4000)  # extra settle before edge measurements

    period_ns, high_ns = await measure_period_and_high(dut.uo_out[0], timeout_us=5000)
    duty = high_ns / period_ns
    expected = 128 / 256  # 0.5

    dut._log.info(f"Measured duty={duty*100:.2f}% (expected {expected*100:.2f}%)")
    assert abs(duty - expected) <= 0.01, f"Duty out of range: got {duty:.4f}, expected {expected:.4f}"
