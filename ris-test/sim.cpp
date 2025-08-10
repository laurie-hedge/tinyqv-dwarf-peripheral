#include "sim.h"

#include "verilated_vcd_c.h"

void SoftwareSim::set_program(Test *test_in) {
	test = test_in;

	default_is_stmt = (test->program_header & 1) == 1;
	memcpy(&line_base, ((char*)&test->program_header) + 1, 1);
	memcpy(&line_range, ((char*)&test->program_header) + 2, 1);
	memcpy(&opcode_base, ((char*)&test->program_header) + 3, 1);

	reset();
	ip = 0;
}

void SoftwareSim::reset() {
	address           = 0;
	file              = 1;
	line              = 1;
	column            = 0;
	is_stmt           = default_is_stmt;
	basic_block_start = false;
	end_sequence      = false;
	prologue_end      = false;
	epiloque_begin    = false;
	discriminator     = 0;

	status           = STATUS_READY;
	needs_full_reset = false;
}

void SoftwareSim::run_to_emit_row_or_illegal() {
	do {
		step_instruction();
	} while (status != STATUS_EMIT_ROW && status != STATUS_ILLEGAL);
}

void SoftwareSim::resume() {
	if (needs_full_reset) {
		reset();
	} else {
		status            = STATUS_READY;
		discriminator     = 0;
		basic_block_start = false;
		prologue_end      = false;
		epiloque_begin    = false;
	}
}

void SoftwareSim::step_instruction() {
	uint8_t opcode = test->program[ip++];
	if (opcode >= opcode_base) {
		uint8_t adjusted_opcode = opcode - opcode_base;
		address                 = (address + (adjusted_opcode / line_range)) & 0xfffffff;
		line                    = line + line_base + (adjusted_opcode % line_range);
		status                  = STATUS_EMIT_ROW;
	} else if (opcode == EXTENDED_OPCODE_START) {
		read_uleb();
		opcode = test->program[ip++];
		if (opcode == DW_LNE_ENDSEQUENCE) {
			status           = STATUS_EMIT_ROW;
			needs_full_reset = true;
			end_sequence     = true;
		} else if (opcode == DW_LNE_SETADDRESS) {
			address = read_u32() & 0xfffffff;
		} else if (opcode == DW_LNE_SETDISCRIMINATOR) {
			discriminator = read_uleb();
		} else {
			status           = STATUS_ILLEGAL;
			needs_full_reset = true;
		}
	} else {
		switch (opcode) {
			case DW_LNS_COPY: {
				status = STATUS_EMIT_ROW;
			} break;
			case DW_LNS_ADVANCEPC: {
				address = (address + read_uleb()) & 0xfffffff;
			} break;
			case DW_LNS_ADVANCELINE: {
				line = (uint16_t)((int16_t)line + read_sleb());
			} break;
			case DW_LNS_SETFILE: {
				file = read_uleb();
			} break;
			case DW_LNS_SETCOLUMN: {
				column = read_uleb() & 0x3ff;
			} break;
			case DW_LNS_NEGATESTMT: {
				is_stmt = !is_stmt;
			} break;
			case DW_LNS_SETBASICBLOCK: {
				basic_block_start = true;
			} break;
			case DW_LNS_CONSTADDPC: {
				uint8_t adjusted_opcode = 255 - opcode_base;
				address                 = (address + (adjusted_opcode / line_range)) & 0xfffffff;
			} break;
			case DW_LNS_FIXEDADVANCEPC: {
				address = (address + read_u16()) & 0xfffffff;
			} break;
			case DW_LNS_SETPROLOGUEEND: {
				prologue_end = true;
			} break;
			case DW_LNS_SETEPILOGUEBEGIN: {
				epiloque_begin = true;
			} break;
			case DW_LNS_SETISA: {
				read_uleb();
			} break;
			default: {
				status           = STATUS_ILLEGAL;
				needs_full_reset = true;
			} break;
		}
	}
}

bool SoftwareSim::program_finished() {
	return (ip >= test->program.size() || status == STATUS_ILLEGAL);
}

uint32_t SoftwareSim::read_uleb() {
	uint32_t result = 0;
	uint32_t shift = 0;
	uint8_t byte;
	do {
		byte = test->program[ip++];
		if (shift < 31) {
			result |= (byte & 0x7F) << shift;
			shift  += 7;
		}
	} while ((byte & 0x80) != 0);
	return result & 0xFFFFFFF;
}

int32_t SoftwareSim::read_sleb() {
	uint32_t result = 0;
	uint32_t shift = 0;
	uint8_t byte;
	do {
		byte = test->program[ip++];
		if (shift < 31) {
			result |= (byte & 0x7F) << shift;
			shift  += 7;
		}
	} while ((byte & 0x80) != 0);
	if (shift < 31) {
		bool sign_bit = ((result >> (shift - 1)) & 1) == 1;
		if (sign_bit) {
			uint32_t sign_mask = 0xffffffff << shift;
			result |= sign_mask;
		}
	}

	int32_t out_result;
	memcpy(&out_result, &result, sizeof(out_result));
	return out_result;
}

uint32_t SoftwareSim::read_u16() {
	uint16_t result;
	memcpy(&result, test->program.data() + ip, 2);
	ip += 2;
	return result;
}

uint32_t SoftwareSim::read_u32() {
	uint32_t result;
	memcpy(&result, test->program.data() + ip, 4);
	ip += 4;
	return result;
}

HardwareSim::HardwareSim() {
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

HardwareSim::~HardwareSim() {
	verilator_sim->final();
}

void HardwareSim::set_program(Test *test_in) {
	test = test_in;
	ip   = 0;

	write_dword(PROGRAM_HEADER, test->program_header);
}

bool HardwareSim::run_to_emit_row_or_illegal() {
	while (true) {
		int timeout     = 1000;
		uint32_t status = read_dword(STATUS);
		while (status == STATUS_BUSY) {
			status = read_dword(STATUS);
			if (--timeout == 0) {
				return false;
			}
		}
		if (status == STATUS_EMIT_ROW || status == STATUS_ILLEGAL) {
			break;
		}
		write_next();
	}
	return true;
}

void HardwareSim::resume() {
	write_dword(STATUS, 0);
}

uint32_t HardwareSim::read_dword(uint8_t reg) {
	verilator_sim->address     = reg;
	verilator_sim->data_read_n = 2;
	run_cycle();
	verilator_sim->data_write_n = 3;
	while (!verilator_sim->data_ready) {
		run_cycle();
	}
	return verilator_sim->data_out;
}

void HardwareSim::run_cycles(uint32_t cycles) {
	for (uint32_t i = 0; i < cycles; ++i) {
		run_cycle();
	}
}

void HardwareSim::run_cycle() {
	verilator_sim->eval();
	verilator_sim->clk = 1;
	verilator_sim->eval();
	verilator_sim->clk = 0;
}

void HardwareSim::write_next() {
	if (ip < test->program.size()) {
		size_t remaining = test->program.size() - ip;
		if (remaining >= 4) {
			uint32_t dword;
			memcpy(&dword, test->program.data() + ip, 4);
			write_dword(PROGRAM_CODE, dword);
			ip += 4;
		} else if (remaining >= 2) {
			uint16_t word;
			memcpy(&word, test->program.data() + ip, 2);
			write_word(PROGRAM_CODE, word);
			ip += 2;
		} else {
			write_byte(PROGRAM_CODE, test->program[ip]);
			ip += 1;
		}
	} else {
		run_cycle();
	}
}

void HardwareSim::write_dword(uint8_t reg, uint32_t dword) {
	verilator_sim->address      = reg;
	verilator_sim->data_in      = dword;
	verilator_sim->data_write_n = 2;
	run_cycle();
	verilator_sim->data_write_n = 3;
	run_cycles(8);
}

void HardwareSim::write_word(uint8_t reg, uint16_t word) {
	verilator_sim->address = reg;
	verilator_sim->data_in = word;
	verilator_sim->data_write_n = 1;
	run_cycle();
	verilator_sim->data_write_n = 3;
	run_cycles(8);
}

void HardwareSim::write_byte(uint8_t reg, uint8_t byte) {
	verilator_sim->address = reg;
	verilator_sim->data_in = byte;
	verilator_sim->data_write_n = 0;
	run_cycle();
	verilator_sim->data_write_n = 3;
	run_cycles(8);
}

double sc_time_stamp() {
	static double time_counter = 0.0;
	time_counter += 1.0;
	return time_counter;
}
