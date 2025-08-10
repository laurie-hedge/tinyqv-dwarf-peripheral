#pragma once

#include <cstddef>
#include <cstdint>
#include <elf.h>
#include <string>
#include <unordered_map>
#include <vector>

struct Span
{
	uint8_t *data;
	size_t size;
};

class ElfFile
{
	bool valid_;
	Elf32_Ehdr header_;
	int fd_;
	size_t file_size_;
	uint8_t *data_;
	std::vector<Elf32_Shdr> section_headers_;
	std::unordered_map<std::string, Elf32_Shdr const *> section_map_;
	std::vector<std::string> file_names_;
	uint8_t *line_table_program_;
	size_t line_table_program_size_;
	uint32_t program_header_;

public:
	ElfFile(char const *file_name);
	~ElfFile();

	bool valid() const { return valid_; }

	std::vector<std::string> const &file_names() { return file_names_; }
	uint32_t program_header() { return program_header_; }
	Span program_code() { return { line_table_program_, line_table_program_size_ }; }
	Span text(size_t start, size_t end);

private:
	std::string get_string(size_t index);
	std::string get_section_name(size_t index);
	Span get_section(std::string const &section_name);
};
