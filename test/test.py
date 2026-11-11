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
    for i, b in enumerate(data):
        dut.ui_in.value = b
        dut.uio_in.value = (mode << ANG_BIT) | ((1 if i == 0 else 0) << START_BIT)
        await FallingEdge(dut.clk)
    dut.ui_in.value = 0
    dut.uio_in.value = mode << ANG_BIT


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


async def read_result(dut):
    out = []
    for _ in range(4):
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
    words = [a & 0xFFFF, b & 0xFFFF]
    data = [x for w in words for x in (w & 0xFF, w >> 8)]

    await send_bytes(dut, mode=0, data=data)
    await wait_done(dut)
    res = await read_result(dut)

    val = sum(byte << (8 * i) for i, byte in enumerate(res))
    if val >= 1 << 31:
        val -= 1 << 32
    dut._log.info(f"mul result bytes={res} -> {val}")
    assert val == a * b, f"expected {a * b}, got {val}"
    assert not (int(dut.uio_out.value) >> ERR_BIT) & 1, "error flag set"


@cocotb.test()
async def test_sincos(dut):
    await reset(dut)

    deg = 30
    angle = round(deg / 360 * 65536)
    data = [angle & 0xFF, angle >> 8]

    await send_bytes(dut, mode=1, data=data)
    await wait_done(dut)
    res = await read_result(dut)

    def s16(lo, hi):
        v = lo | (hi << 8)
        return v - 65536 if v >= 32768 else v

    sin_v = s16(res[0], res[1])
    cos_v = s16(res[2], res[3])
    exp_sin = round(math.sin(math.radians(deg)) * 16384)
    exp_cos = round(math.cos(math.radians(deg)) * 16384)
    dut._log.info(f"sin={sin_v} (exp {exp_sin}), cos={cos_v} (exp {exp_cos})")

    assert abs(sin_v - exp_sin) <= 16
    assert abs(cos_v - exp_cos) <= 16
