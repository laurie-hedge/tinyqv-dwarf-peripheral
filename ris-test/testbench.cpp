#include <iostream>

#include "testbench.h"

bool Testbench::run_test(Test *test) {
	hwsim.set_program(test);
	swsim.set_program(test);
	while (true) {
		swsim.run_to_emit_row_or_illegal();
		if (!hwsim.run_to_emit_row_or_illegal()) {
			std::cerr << "MISMATCH: hardware timeout\n";
			break;
		}
		if (compare_state()) {
			if (swsim.program_finished()) {
				return true;
			}
			hwsim.resume();
			swsim.resume();
		} else {
			break;
		}
	}

	return false;
}

bool Testbench::compare_state() {
	uint32_t address        = hwsim.read_dword(AM_ADDRESS);
	uint32_t file_discrim   = hwsim.read_dword(AM_FILE_DISCRIM);
	uint32_t line_col_flags = hwsim.read_dword(AM_LINE_COL_FLAGS);

	uint16_t file          = file_discrim & 0xFFFF;
	uint16_t line          = line_col_flags & 0xFFFF;
	uint16_t column        = (line_col_flags >> 16) & 0x3FF;
	bool is_stmt           = (line_col_flags >> 26) & 1;
	bool basic_block_start = (line_col_flags >> 27) & 1;
	bool end_sequence      = (line_col_flags >> 28) & 1;
	bool prologue_end      = (line_col_flags >> 29) & 1;
	bool epiloque_begin    = (line_col_flags >> 30) & 1;
	uint16_t discriminator = file_discrim >> 16;

	if (address != swsim.address) {
		std::cerr << "mismatch on address: 0x" << std::hex << address << " (dut) != 0x" << swsim.address << " (ref)\n";
		return false;
	}
	if (file != swsim.file) {
		std::cerr << "mismatch on file: 0x" << std::hex << file << " (dut) != 0x" << swsim.file << " (ref)\n";
		return false;
	}
	if (line != swsim.line) {
		std::cerr << "mismatch on line: 0x" << std::hex << line << " (dut) != 0x" << swsim.line << " (ref)\n";
		return false;
	}
	if (column != swsim.column) {
		std::cerr << "mismatch on column: 0x" << std::hex << column << " (dut) != 0x" << swsim.column << " (ref)\n";
		return false;
	}
	if (is_stmt != swsim.is_stmt) {
		std::cerr << "mismatch on is_stmt: " << is_stmt << " (dut) != " << swsim.is_stmt << " (ref)\n";
		return false;
	}
	if (basic_block_start != swsim.basic_block_start) {
		std::cerr << "mismatch on basic_block_start: " << basic_block_start << " (dut) != " << swsim.basic_block_start << " (ref)\n";
		return false;
	}
	if (end_sequence != swsim.end_sequence) {
		std::cerr << "mismatch on end_sequence: " << end_sequence << " (dut) != " << swsim.end_sequence << " (ref)\n";
		return false;
	}
	if (prologue_end != swsim.prologue_end) {
		std::cerr << "mismatch on prologue_end: " << prologue_end << " (dut) != " << swsim.prologue_end << " (ref)\n";
		return false;
	}
	if (epiloque_begin != swsim.epiloque_begin) {
		std::cerr << "mismatch on epiloque_begin: " << epiloque_begin << " (dut) != " << swsim.epiloque_begin << " (ref)\n";
		return false;
	}
	if (discriminator != swsim.discriminator) {
		std::cerr << "mismatch on discriminator: 0x" << std::hex << discriminator << " (dut) != 0x" << swsim.discriminator << " (ref)\n";
		return false;
	}

	return true;
}
