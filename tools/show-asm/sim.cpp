#include "sim.h"

#include "verilated_vcd_c.h"

#define STATUS_READY    0x0
#define STATUS_EMIT_ROW 0x1
#define STATUS_BUSY     0x2
#define STATUS_ILLEGAL  0x3

#define PROGRAM_HEADER    0x00
#define PROGRAM_CODE      0x04
#define AM_ADDRESS        0x08
#define AM_FILE_DISCRIM   0x0C
#define AM_LINE_COL_FLAGS 0x10
#define STATUS            0x14
#define INFO              0x18

Sim::Sim() {
	Verilated::traceEverOn(true);

	verilator_sim = std::make_unique<Vtqvp_laurie_dwarf_line_table_accelerator>();
	verilator_sim->clk          = 0;
	verilator_sim->rst_n        = 0;
	verilator_sim->ui_in        = 0;
	verilator_sim->address      = 0;
	verilator_sim->data_in      = 0;
	verilator_sim->data_write_n = 3;
	verilator_sim->data_read_n  = 3;
	run_cycle();
	verilator_sim->rst_n = 1;
	run_cycle();
}

Sim::~Sim() {
	verilator_sim->final();
}

LineTable Sim::run_program(uint32_t program_header, uint8_t *program_code, size_t program_code_size) {
	LineTable line_table;

	write_dword(PROGRAM_HEADER, program_header);

	size_t ip = 0;

	while (ip < program_code_size) {
		if (ip + 4 <= program_code_size) {
			uint32_t code;
			memcpy(&code, program_code + ip, sizeof(code));
			write_dword(PROGRAM_CODE, code);
			ip += sizeof(code);
		} else if (ip + 2 <= program_code_size) {
			uint16_t code;
			memcpy(&code, program_code + ip, sizeof(code));
			write_word(PROGRAM_CODE, code);
			ip += sizeof(code);
		} else {
			write_byte(PROGRAM_CODE, program_code[ip]);
			ip += 1;
		}

		uint32_t status = read_dword(STATUS);
		while (status == STATUS_BUSY) {
			status = read_dword(STATUS);
		}
		if (status == STATUS_EMIT_ROW) {
			uint32_t const address        = read_dword(AM_ADDRESS);
			uint32_t const file_discrim   = read_dword(AM_FILE_DISCRIM);
			uint32_t const line_col_flags = read_dword(AM_LINE_COL_FLAGS);

			LineTableRow row;
			row.address        = address;
			row.file           = file_discrim & 0xFFFF;
			row.line           = line_col_flags & 0xFFFF;
			row.column         = (line_col_flags >> 16) & 0x3FF;
			row.is_stmt        = ((line_col_flags >> 26) & 1) == 1;
			row.basic_block    = ((line_col_flags >> 27) & 1) == 1;
			row.end_sequence   = ((line_col_flags >> 28) & 1) == 1;
			row.prologue_end   = ((line_col_flags >> 29) & 1) == 1;
			row.epilogue_begin = ((line_col_flags >> 30) & 1) == 1;
			line_table.push_back(row);

			write_dword(STATUS, 0);
		} else if (status == STATUS_ILLEGAL) {
			return { };
		}
	}

	return line_table;
}

void Sim::run_cycle() {
	verilator_sim->eval();
	verilator_sim->clk = 1;
	verilator_sim->eval();
	verilator_sim->clk = 0;
}

void Sim::run_cycles(uint32_t cycles) {
	for (uint32_t i = 0; i < cycles; ++i) {
		run_cycle();
	}
}

void Sim::write_dword(uint8_t reg, uint32_t dword) {
	verilator_sim->address      = reg;
	verilator_sim->data_in      = dword;
	verilator_sim->data_write_n = 2;
	run_cycle();
	verilator_sim->data_write_n = 3;
	run_cycles(8);
}

void Sim::write_word(uint8_t reg, uint16_t word) {
	verilator_sim->address = reg;
	verilator_sim->data_in = word;
	verilator_sim->data_write_n = 1;
	run_cycle();
	verilator_sim->data_write_n = 3;
	run_cycles(8);
}

void Sim::write_byte(uint8_t reg, uint8_t byte) {
	verilator_sim->address = reg;
	verilator_sim->data_in = byte;
	verilator_sim->data_write_n = 0;
	run_cycle();
	verilator_sim->data_write_n = 3;
	run_cycles(8);
}

uint32_t Sim::read_dword(uint8_t reg) {
	verilator_sim->address     = reg;
	verilator_sim->data_read_n = 2;
	run_cycle();
	verilator_sim->data_write_n = 3;
	while (!verilator_sim->data_ready) {
		run_cycle();
	}
	return verilator_sim->data_out;
}

double sc_time_stamp() {
	static double time_counter = 0.0;
	time_counter += 1.0;
	return time_counter;
}
