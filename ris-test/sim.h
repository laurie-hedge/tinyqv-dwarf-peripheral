#pragma once

#include <cstdint>
#include <memory>

#include "Vtqvp_laurie_dwarf_line_table_accelerator.h"

#include "test.h"

#define STATUS_READY    0x0
#define STATUS_EMIT_ROW 0x1
#define STATUS_BUSY     0x2
#define STATUS_ILLEGAL  0x3

#define DW_LNS_COPY             0x01
#define DW_LNS_ADVANCEPC        0x02
#define DW_LNS_ADVANCELINE      0x03
#define DW_LNS_SETFILE          0x04
#define DW_LNS_SETCOLUMN        0x05
#define DW_LNS_NEGATESTMT       0x06
#define DW_LNS_SETBASICBLOCK    0x07
#define DW_LNS_CONSTADDPC       0x08
#define DW_LNS_FIXEDADVANCEPC   0x09
#define DW_LNS_SETPROLOGUEEND   0x0A
#define DW_LNS_SETEPILOGUEBEGIN 0x0B
#define DW_LNS_SETISA           0x0C

#define EXTENDED_OPCODE_START   0x00
#define DW_LNE_ENDSEQUENCE      0x01
#define DW_LNE_SETADDRESS       0x02
#define DW_LNE_SETDISCRIMINATOR 0x04

#define PROGRAM_HEADER    0x00
#define PROGRAM_CODE      0x04
#define AM_ADDRESS        0x08
#define AM_FILE_DISCRIM   0x0C
#define AM_LINE_COL_FLAGS 0x10
#define STATUS            0x14
#define INFO              0x18

class SoftwareSim
{
	Test *test;

	bool default_is_stmt;
	int8_t line_base;
	uint8_t line_range;
	uint8_t opcode_base;

	size_t ip;
	bool needs_full_reset;

public:
	uint32_t address;
	uint16_t file;
	uint16_t line;
	uint16_t column;
	bool is_stmt;
	bool basic_block_start;
	bool end_sequence;
	bool prologue_end;
	bool epiloque_begin;
	uint16_t discriminator;

	uint8_t status;

public:
	void reset();
	void set_program(Test *test_in);
	void run_to_emit_row_or_illegal();
	void resume();
	void step_instruction();
	bool program_finished();

private:
	uint32_t read_uleb();
	int32_t read_sleb();
	uint32_t read_u16();
	uint32_t read_u64();
};

class HardwareSim
{
	std::unique_ptr<Vtqvp_laurie_dwarf_line_table_accelerator> verilator_sim;

	Test *test;

	size_t ip;

public:
	HardwareSim();
	~HardwareSim();

	void set_program(Test *test_in);
	bool run_to_emit_row_or_illegal();
	void resume();

	uint32_t read_dword(uint8_t reg);

private:
	void run_cycles(uint32_t cycles);
	void run_cycle();
	void write_next();
	void write_dword(uint8_t reg, uint32_t dword);
	void write_word(uint8_t reg, uint16_t word);
	void write_byte(uint8_t reg, uint8_t byte);
};
