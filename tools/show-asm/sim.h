#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include "Vtqvp_laurie_dwarf_line_table_accelerator.h"

struct LineTableRow
{
	uint32_t address;
	uint16_t file;
	uint16_t line;
	uint16_t column;
	bool is_stmt;
	bool basic_block;
	bool end_sequence;
	bool prologue_end;
	bool epilogue_begin;
};

using LineTable = std::vector<LineTableRow>;

class Sim
{
	std::unique_ptr<Vtqvp_laurie_dwarf_line_table_accelerator> verilator_sim;

public:
	Sim();
	~Sim();

	LineTable run_program(uint32_t program_header, uint8_t *program_code, size_t program_code_size);

private:
	void run_cycle();
	void run_cycles(uint32_t cycles);
	void write_dword(uint8_t reg, uint32_t dword);
	void write_word(uint8_t reg, uint16_t word);
	void write_byte(uint8_t reg, uint8_t byte);
	uint32_t read_dword(uint8_t reg);
};
