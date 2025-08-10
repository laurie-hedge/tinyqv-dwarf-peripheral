#include <cstdint>
#include <iomanip>
#include <iostream>

#include "elf_file.h"
#include "riscv-disassembler/src/riscv-disas.h"

void print_instruction_range(size_t start, Span const &code) {
	char buffer[128];
	for (size_t i = 0; i < code.size;) {
		rv_inst inst;
		size_t length;
		inst_fetch(code.data + i, &inst, &length);
		disasm_inst(buffer, sizeof(buffer), rv32, start + i, inst);
		std::cout << std::hex << std::setw(8) << std::setfill('0') << (start + i) << ":  " <<
			buffer << '\n';
		i += length;
	}
}
