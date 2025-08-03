#include <fstream>

#include "test.h"

void Test::save(char const *test_file_name) {
	std::ofstream file(test_file_name, std::ios::binary);
	file.write((char*)&program_header, sizeof(program_header));
	file.write((char*)program.data(), program.size());
	file.close();
}

void Test::load(char const *test_file_name) {
	std::ifstream file(test_file_name, std::ios::binary);
	file.read((char*)&program_header, sizeof(program_header));
	uint8_t byte;
	program.clear();
	while (file.read((char*)&byte, 1)) {
		program.push_back(byte);
	}
}
