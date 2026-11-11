import math
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

START_BIT = 7
ANG_BIT   = 6
DONE_BIT  = 4
ERR_BIT   = 3
BUSY_BIT  = 5


async def send_bytes(dut, mode, data):
    await FallingEdge(dut.clk)
    dut.ui_in.value = 0
    dut.uio_in.value = (mode << ANG_BIT) | (1 << START_BIT)
    await FallingEdge(dut.clk)
    for b in data:
        dut.ui_in.value = b
        dut.uio_in.value = mode << ANG_BIT
        await FallingEdge(dut.clk)
    dut.ui_in.value = 0


async def wait_done(dut, timeout=100):
    for _ in range(timeout):
        flags = int(dut.uio_out.value)
        if (flags >> DONE_BIT) & 1:
            return
        await FallingEdge(dut.clk)
    flags = int(dut.uio_out.value)
    assert False, (
        f"timeout: busy={(flags >> BUSY_BIT) & 1} "
        f"done={(flags >> DONE_BIT) & 1} error={(flags >> ERR_BIT) & 1}"
    )


async def read_result(dut, n):
    out = []
    for _ in range(n):
        out.append(int(dut.uo_out.value))
        await FallingEdge(dut.clk)
    return out


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_multiply(dut):
    await reset(dut)

    a, b = 7, -3
    await send_bytes(dut, mode=0, data=[a & 0xFF, b & 0xFF])
    await wait_done(dut)
    res = await read_result(dut, 2)

    val = res[0] | (res[1] << 8)
    if val >= 1 << 15:
        val -= 1 << 16
    dut._log.info(f"mul result bytes={res} -> {val}")
    assert val == a * b, f"expected {a * b}, got {val}"
    assert not (int(dut.uio_out.value) >> ERR_BIT) & 1, "error flag set"


@cocotb.test()
async def test_sincos(dut):
    await reset(dut)

    angle = round(30 / 360 * 65536)
    await send_bytes(dut, mode=1, data=[angle & 0xFF, angle >> 8])
    await wait_done(dut)
    res = await read_result(dut, 4)

    def s16(lo, hi):
        v = lo | (hi << 8)
        return v - 65536 if v >= 32768 else v

    cos_v = s16(res[0], res[1])
    sin_v = s16(res[2], res[3])
    rad = math.radians(angle / 65536 * 360)
    exp_cos = round(math.cos(rad) * 16384)
    exp_sin = round(math.sin(rad) * 16384)
    dut._log.info(f"cos={cos_v} (exp {exp_cos}), sin={sin_v} (exp {exp_sin})")

    assert abs(cos_v - exp_cos) <= 16
    assert abs(sin_v - exp_sin) <= 16
