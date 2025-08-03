#pragma once

#include <cstdint>
#include <vector>

struct Test
{
	uint32_t program_header = 0;
	std::vector<uint8_t> program;

	void save(char const *test_file_name);
	void load(char const *test_file_name);
};
