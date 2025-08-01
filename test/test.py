# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

# When submitting your design, change this to the peripheral number
# in peripherals.v.  e.g. if your design is i_user_peri05, set this to 5.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 0

class MmReg:
    PROGRAM_HEADER    = 0
    PROGRAM_CODE      = 1
    AM_ADDRESS        = 2
    AM_FILE_DISCRIM   = 3
    AM_LINE_COL_FLAGS = 4
    STATUS            = 5
    INFO              = 6

class Status:
    READY    = 0
    EMIT_ROW = 1

class StandardOpcode:
    DwLnsCopy             = 0x01
    DwLnsAdvancePc        = 0x02
    DwLnsAdvanceLine      = 0x03
    DwLnsSetFile          = 0x04
    DwLnsSetColumn        = 0x05
    DwLnsNegateStmt       = 0x06
    DwLnsSetBasicBlock    = 0x07
    DwLnsConstAddPc       = 0x08
    DwLnsFixedAdvancePc   = 0x09
    DwLnsSetPrologueEnd   = 0x0A
    DwLnsSetEpilogueBegin = 0x0B
    DwLnsSetIsa           = 0x0C

class ExtendedOpcode:
    START                 = 0x00
    DwLneEndSequence      = 0x01
    DwLneSetAddress       = 0x02
    DwLneSetDiscriminator = 0x04

@cocotb.test()
async def test_register_read_write_reset(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test default register values
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER)    == 0x0
    assert await tqv.read_word_reg(MmReg.PROGRAM_CODE)      == 0x0
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS)        == 0x0
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM)   == 0x1
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1
    assert await tqv.read_word_reg(MmReg.STATUS)            == Status.READY
    assert await tqv.read_word_reg(MmReg.INFO)              == 0x00000155

    # test default value of is_stmt updated on new program header
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x00000001)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x4000001
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x00000000)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1

    # test writes to read only registers are ignored
    await tqv.write_word_reg(MmReg.AM_ADDRESS, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.AM_FILE_DISCRIM, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM) == 0x1
    await tqv.write_word_reg(MmReg.AM_LINE_COL_FLAGS, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1
    await tqv.write_word_reg(MmReg.STATUS, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.STATUS) == Status.READY
    await tqv.write_word_reg(MmReg.INFO, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.INFO) == 0x00000155

    # test writes to read-write registers
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0xABCD2301)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xABCD2301

    # test writes to write-only registers
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0xABCD1234)
    assert await tqv.read_word_reg(MmReg.PROGRAM_CODE) == 0x0

    # test writes to read only regions of writable registers are ignored
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0xFFFFFFFF)
    assert await tqv.read_word_reg(MmReg.PROGRAM_HEADER) == 0xFFFFFF01
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x0)

    # test accesses to non-existent registers do nothing
    real_registers = set([
        MmReg.PROGRAM_HEADER,
        MmReg.PROGRAM_CODE,
        MmReg.AM_ADDRESS,
        MmReg.AM_FILE_DISCRIM,
        MmReg.AM_LINE_COL_FLAGS,
        MmReg.STATUS,
        MmReg.INFO,
    ])
    for illegal_reg in [i for i in range(64) if i not in real_registers]:
        await tqv.write_word_reg(illegal_reg, 0xFFFFFFFF)
        assert await tqv.read_word_reg(illegal_reg) == 0x0

@cocotb.test()
async def test_dw_lns_copy(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test copy instruction emits row via an interrupt
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    await ClockCycles(dut.clk, 1)
    assert await tqv.is_interrupt_asserted()
    assert await tqv.read_word_reg(MmReg.STATUS)            == Status.EMIT_ROW
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS)        == 0x0
    assert await tqv.read_byte_reg(MmReg.AM_FILE_DISCRIM)   == 0x1
    assert await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS) == 0x1

    # test clear status register de-asserts
    await tqv.write_word_reg(MmReg.STATUS, 0)
    assert not await tqv.is_interrupt_asserted()

    # test two copy instructions in a row
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsCopy)
    await ClockCycles(dut.clk, 5)
    assert await tqv.is_interrupt_asserted()
    await tqv.write_hword_reg(MmReg.STATUS, 1)
    assert not await tqv.is_interrupt_asserted()
    await ClockCycles(dut.clk, 1)
    assert await tqv.is_interrupt_asserted()
    await tqv.write_byte_reg(MmReg.STATUS, 254)
    assert not await tqv.is_interrupt_asserted()
    await ClockCycles(dut.clk, 5)
    assert not await tqv.is_interrupt_asserted()

@cocotb.test()
async def test_dw_lns_advance_pc(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test advance pc with one byte operand
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (4 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x4
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with two byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x7494 << 8) | StandardOpcode.DwLnsAdvancePc)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x3A18
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with three byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x018182 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x7A9A
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with four byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x8392A4 << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | 0x04)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x8143BE
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with odd operand ignores lsb
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x0183 << 8) | StandardOpcode.DwLnsAdvancePc)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x814440
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test advance pc with overflowing operand
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsAdvancePc)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0x80808082)
    for i in range(10):
        await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0xFFFFFFFF)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0x01808080)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x814442
    await tqv.write_word_reg(MmReg.STATUS, 0)

    # test overflow of address register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xFFFFFF << 8) | StandardOpcode.DwLnsAdvancePc)
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | 0x7F)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x814440
    await tqv.write_word_reg(MmReg.STATUS, 0)

@cocotb.test()
async def test_dw_lns_advance_line(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test advance line with one byte positive operand
    assert await read_sm_line(tqv) == 0x1
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (2 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0x3
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with one byte negative operand
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x7F << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with two byte positive operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x1298 << 8) | StandardOpcode.DwLnsAdvanceLine)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0x91A
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with two byte negative operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x6DE8 << 8) | StandardOpcode.DwLnsAdvanceLine)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with three byte positive operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x039298 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0xC91A
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test advance line with three byte negative operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x7CEDE8 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test underflow of line register
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x7B << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0xFFFD
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test overflow of line register
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x05 << 8) | StandardOpcode.DwLnsAdvanceLine)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_line(tqv) == 0x2
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_file(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set file with one byte operand
    assert await read_sm_file(tqv) == 0x1
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x05 << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_file(tqv) == 0x5
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set file with two byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x0185 << 8) | StandardOpcode.DwLnsSetFile)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_file(tqv) == 0x85
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set file with three byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x03A2B1 << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_file(tqv) == 0xD131
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test overflow file register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x07B3C4 << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_file(tqv) == 0xD9C4
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_column(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set column with one byte operand
    assert await read_sm_column(tqv) == 0x0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x05 << 8) | StandardOpcode.DwLnsSetColumn)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_column(tqv) == 0x5
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set column with two byte operand
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x0185 << 8) | StandardOpcode.DwLnsSetColumn)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_column(tqv) == 0x85
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test overflow column register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x03A2B1 << 8) | StandardOpcode.DwLnsSetColumn)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_column(tqv) == 0x131
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_negate_stmt(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test flip from 0 to 1
    assert await read_sm_is_stmt(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsNegateStmt)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_is_stmt(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test flip from 1 to 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsNegateStmt)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_is_stmt(tqv) == 0
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test two back to back flips
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsNegateStmt << 8) | StandardOpcode.DwLnsNegateStmt)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_is_stmt(tqv) == 0
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test three back to back flips
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (StandardOpcode.DwLnsNegateStmt << 16) | (StandardOpcode.DwLnsNegateStmt << 8) | StandardOpcode.DwLnsNegateStmt)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_is_stmt(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_basic_block(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test setting basic block
    assert await read_sm_basic_block(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetBasicBlock)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_basic_block(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset basic block
    assert await read_sm_basic_block(tqv) == 0

    # test setting basic block twice back to back
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetBasicBlock << 8) | StandardOpcode.DwLnsSetBasicBlock)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_basic_block(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_const_add_pc(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # TODO: implement along with special instructions

@cocotb.test()
async def test_dw_lns_fixed_advance_pc(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test fixed advance pc
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0x1234 << 8) | StandardOpcode.DwLnsFixedAdvancePc)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x1234
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test fixed advance pc with odd operand ignores lsb
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | (0xABCD << 8) | StandardOpcode.DwLnsFixedAdvancePc)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xBE00
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_prologue_end(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set prologue end
    assert await read_sm_prologue_end(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetPrologueEnd)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_prologue_end(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset prologue end
    assert await read_sm_prologue_end(tqv) == 0

    # test set prologue end twice back to back
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetPrologueEnd << 8) | StandardOpcode.DwLnsSetPrologueEnd)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_prologue_end(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_epilogue_begin(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set epilogue begin
    assert await read_sm_epilogue_begin(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 8) | StandardOpcode.DwLnsSetEpilogueBegin)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_epilogue_begin(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset epilogue begin
    assert await read_sm_epilogue_begin(tqv) == 0

    # test set epilogue begin twice back to back
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetEpilogueBegin << 8) | StandardOpcode.DwLnsSetEpilogueBegin)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_epilogue_begin(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lns_set_isa(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set isa with single byte operand is correctly parsed as a nop
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x01 << 8) | StandardOpcode.DwLnsSetIsa)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test set isa with multi byte operand is correctly parsed as a nop
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xFFFFFF << 8) | StandardOpcode.DwLnsSetIsa)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0xFFFFFFFF)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | 0x7FFFFF)
    assert await wait_for_assert(dut, tqv, 10)
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lne_end_sequence(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test end sequence sets end sequence flag
    assert await read_sm_end_sequence(tqv) == 0
    await tqv.write_hword_reg(MmReg.PROGRAM_CODE, (0x01 << 8) | ExtendedOpcode.START)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, ExtendedOpcode.DwLneEndSequence)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_end_sequence(tqv) == 1
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after end sequence reset end sequence flag
    assert await read_sm_epilogue_begin(tqv) == 0

    # test end sequence resets entire state machine after restart
    await tqv.write_word_reg(MmReg.PROGRAM_HEADER, 0x00000001)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    assert await read_sm_file(tqv)           == 1
    assert await read_sm_line(tqv)           == 1
    assert await read_sm_column(tqv)         == 0
    assert await read_sm_is_stmt(tqv)        == 1
    assert await read_sm_basic_block(tqv)    == 0
    assert await read_sm_end_sequence(tqv)   == 0
    assert await read_sm_prologue_end(tqv)   == 0
    assert await read_sm_epilogue_begin(tqv) == 0
    assert await read_sm_discrim(tqv)        == 0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x04 << 24) | (StandardOpcode.DwLnsAdvanceLine << 16) | (0x0A << 8) | StandardOpcode.DwLnsSetFile)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsSetBasicBlock << 24) | (StandardOpcode.DwLnsNegateStmt << 16) | (0x0B << 8) | StandardOpcode.DwLnsSetColumn)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x02 << 24) | (ExtendedOpcode.START << 16) | (StandardOpcode.DwLnsSetEpilogueBegin << 8) | StandardOpcode.DwLnsSetPrologueEnd)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x01 << 24) | (ExtendedOpcode.START << 16) | (0x06 << 8) | ExtendedOpcode.DwLneSetDiscriminator)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, ExtendedOpcode.DwLneEndSequence)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_file(tqv)           == 10
    assert await read_sm_line(tqv)           == 5
    assert await read_sm_column(tqv)         == 11
    assert await read_sm_is_stmt(tqv)        == 0
    assert await read_sm_basic_block(tqv)    == 1
    assert await read_sm_end_sequence(tqv)   == 1
    assert await read_sm_prologue_end(tqv)   == 1
    assert await read_sm_epilogue_begin(tqv) == 1
    assert await read_sm_discrim(tqv)        == 6
    await tqv.write_byte_reg(MmReg.STATUS, 1)
    assert await read_sm_file(tqv)           == 1
    assert await read_sm_line(tqv)           == 1
    assert await read_sm_column(tqv)         == 0
    assert await read_sm_is_stmt(tqv)        == 1
    assert await read_sm_basic_block(tqv)    == 0
    assert await read_sm_end_sequence(tqv)   == 0
    assert await read_sm_prologue_end(tqv)   == 0
    assert await read_sm_epilogue_begin(tqv) == 0
    assert await read_sm_discrim(tqv)        == 0

@cocotb.test()
async def test_dw_lne_set_address(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set address
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0x0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xDD << 24) | (ExtendedOpcode.DwLneSetAddress << 16) | (0x09 << 8) | ExtendedOpcode.START)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, 0x44AABBCC)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | 0x112233)
    assert await wait_for_assert(dut, tqv, 10)
    assert await tqv.read_word_reg(MmReg.AM_ADDRESS) == 0xABBCCDC
    await tqv.write_byte_reg(MmReg.STATUS, 1)

@cocotb.test()
async def test_dw_lne_set_discriminator(dut):
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    tqv = TinyQV(dut, PERIPHERAL_NUM)
    await tqv.reset()

    # test set discriminator
    assert await read_sm_discrim(tqv) == 0
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0x05 << 24) | (ExtendedOpcode.DwLneSetDiscriminator << 16) | (0x02 << 8) | ExtendedOpcode.START)
    await tqv.write_byte_reg(MmReg.PROGRAM_CODE, StandardOpcode.DwLnsCopy)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_discrim(tqv) == 5
    await tqv.write_byte_reg(MmReg.STATUS, 1)

    # test restart after copy reset discriminator register
    assert await read_sm_discrim(tqv) == 0

    # test overflow discriminator register
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (0xFF << 24) | (ExtendedOpcode.DwLneSetDiscriminator << 16) | (0x05 << 8) | ExtendedOpcode.START)
    await tqv.write_word_reg(MmReg.PROGRAM_CODE, (StandardOpcode.DwLnsCopy << 24) | 0x7FFFFF)
    assert await wait_for_assert(dut, tqv, 10)
    assert await read_sm_discrim(tqv) == 0xFFFF
    await tqv.write_byte_reg(MmReg.STATUS, 1)

async def wait_for_assert(dut, tqv, timeout):
    while timeout > 0:
        await ClockCycles(dut.clk, 1)
        if await tqv.is_interrupt_asserted():
            return True
        else:
            timeout -= 1
    return False

async def read_sm_line(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return line_col_flags & 0xFFFF

async def read_sm_column(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 16) & 0x3FF

async def read_sm_is_stmt(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 26) & 1

async def read_sm_basic_block(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 27) & 1

async def read_sm_end_sequence(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 28) & 1

async def read_sm_prologue_end(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 29) & 1

async def read_sm_epilogue_begin(tqv):
    line_col_flags = await tqv.read_word_reg(MmReg.AM_LINE_COL_FLAGS)
    return (line_col_flags >> 30) & 1

async def read_sm_file(tqv):
    file_descrim = await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM)
    return file_descrim & 0xFFFF

async def read_sm_discrim(tqv):
    file_descrim = await tqv.read_word_reg(MmReg.AM_FILE_DISCRIM)
    return (file_descrim >> 16) & 0xFFFF
