#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "elf_file.h"
#include "sim.h"

void print_instruction_range(size_t start, Span const &code);

int main(int argc, char **argv) {
	if (argc != 2) {
		std::cerr << "usage: show-asm <elf-file>\n";
		return 0;
	}

	ElfFile elf_file { argv[1] };

	if (!elf_file.valid()) {
		return -1;
	}

	uint32_t program_header = elf_file.program_header();
	Span program_code       = elf_file.program_code();

	Sim sim;
	LineTable line_table = sim.run_program(program_header, program_code.data, program_code.size);

	while (true) {
		std::string input;
		std::cout << "> ";
		getline(std::cin, input);

		std::vector<std::string> parts;
		std::string part;
		std::istringstream iss(input);
		while (iss >> part) {
			parts.push_back(part);
		}

		if (parts.empty()) {
			continue;
		}

		if (parts[0] == "q") {
			break;
		} else if (parts[0] == "ls") {
			if (parts.size() < 2) {
				std::cout << "usage: ls [files]\n";
			} else if (parts[1] == "files") {
				std::vector<std::string> const &file_names = elf_file.file_names();
				for (size_t i = 1; i < file_names.size(); ++i) {
					std::cout << i << ". " << file_names[i] << '\n';
				}
			} else {
				std::cout << "usage: ls [files]\n";
			}
		} else if (parts[0] == "p") {
			if (parts.size() < 3) {
				std::cout << "usage: p <file-index> <line-number>\n";
			} else {
				int file_index  = std::stoi(parts[1]);
				int line_number = std::stoi(parts[2]);
				std::vector<std::pair<size_t, size_t>> address_ranges;
				size_t address_start;
				bool in_range = false;
				for (size_t i = 0; i < line_table.size(); ++i) {
					if (in_range) {
						if (line_table[i].file != file_index || line_table[i].line != line_number ||
							line_table[i].end_sequence) {
							in_range = false;
							address_ranges.push_back({ address_start, line_table[i].address });
						}
					} else {
						if (line_table[i].file == file_index && line_table[i].line == line_number &&
							!line_table[i].end_sequence) {
							in_range = true;
							address_start = line_table[i].address;
						}
					}
				}
				for (auto const &range : address_ranges) {
					auto const [start, end] = range;
					print_instruction_range(start, elf_file.text(start, end));
				}
			}
		}
	}

	return 0;
}
