#include <cstring>
#include <iostream>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "dwarf.h"
#include "elf_file.h"

static uint8_t *skip_leb(uint8_t *cur) {
	while (*cur & 0x80) {
		cur += 1;
	}
	return cur + 1;
}

static uint64_t parse_uleb(uint8_t *&cur) {
	uint64_t shift = 0;
	uint64_t result = 0;
	do {
		result |= (uint64_t)*cur << shift;
		shift += 7;
		cur += 1;
	} while (*cur & 0x80);
	return result;
}

#define DW_FORM_data2     0x05
#define DW_FORM_data4     0x06
#define DW_FORM_data8     0x07
#define DW_FORM_string    0x08
#define DW_FORM_block     0x09
#define DW_FORM_data1     0x0B
#define DW_FORM_strp      0x0E
#define DW_FORM_udata     0x0F
#define DW_FORM_strp_sup  0x1D
#define DW_FORM_data16    0x1E
#define DW_FORM_line_strp 0x1F

std::string parse_string(uint8_t *&cur, uint64_t form_code, uint8_t *debug_str_data, uint8_t *debug_line_str_data) {
	switch (form_code) {
		case DW_FORM_string: {
			std::string result((char *)cur);
			cur += result.size() + 1;
			return result;
		}
		case DW_FORM_strp: {
			uint32_t offset;
			memcpy(&offset, cur, sizeof(offset));
			cur += sizeof(offset);
			std::string result((char *)debug_str_data + offset);
			return result;
		}
		case DW_FORM_line_strp: {
			uint32_t offset;
			memcpy(&offset, cur, sizeof(offset));
			cur += sizeof(offset);
			std::string result((char *)debug_line_str_data + offset);
			return result;
		}
		default: {
			return "";
		}
	}
}

uint64_t parse_unsigned(uint8_t *&cur, uint64_t form_code) {
	switch (form_code) {
		case DW_FORM_data2: {
			uint16_t result;
			memcpy(&result, cur, sizeof(result));
			cur += sizeof(result);
			return result;
		}
		case DW_FORM_data4: {
			uint32_t result;
			memcpy(&result, cur, sizeof(result));
			cur += sizeof(result);
			return result;
		}
		case DW_FORM_data8: {
			uint64_t result;
			memcpy(&result, cur, sizeof(result));
			cur += sizeof(result);
			return result;
		}
		case DW_FORM_block: {
			uint64_t block_size = parse_uleb(cur);
			uint64_t result = 0;
			if (block_size <= sizeof(result)) {
				memcpy(&result, cur, block_size);
			} else {
				memcpy(&result, cur, sizeof(result));
			}
			cur += block_size;
			return result;
		}
		case DW_FORM_data1: {
			uint8_t result;
			memcpy(&result, cur, sizeof(result));
			cur += sizeof(result);
			return result;
		}
		case DW_FORM_udata: {
			return parse_uleb(cur);
		}
		default: {
			return 0;
		}
	}
}

uint8_t *skip_data16(uint8_t *cur) {
	return cur + 16;
}

ElfFile::ElfFile(char const *file_name) {
	valid_ = false;
	data_ = nullptr;

	fd_ = open(file_name, O_RDONLY);
	if (fd_ < 0) {
		std::cerr << "failed to open file " << file_name << "\n";
		exit(-1);
	}

	struct stat stats;
	if (fstat(fd_, &stats) < 0) {
		std::cerr << "failed to read file stats\n";
		return;
	}
	file_size_ = stats.st_size;

	void *ret = mmap(0, file_size_, PROT_READ, MAP_SHARED, fd_, 0);
	if (ret == MAP_FAILED) {
		std::cerr << "failed to mmap file\n";
		return;
	}
	data_ = (uint8_t *)ret;

	memcpy(&header_, data_, sizeof(header_));

	if (header_.e_ident[EI_MAG0] != ELFMAG0 || header_.e_ident[EI_MAG1] != ELFMAG1 ||
	    header_.e_ident[EI_MAG2] != ELFMAG2 || header_.e_ident[EI_MAG3] != ELFMAG3) {
		std::cerr << "invalid elf file\n";
		return;
	}

	if (header_.e_ident[EI_CLASS] != ELFCLASS32) {
		std::cerr << "only 32-bit elf files are supported\n";
		return;
	}

	if (header_.e_ident[EI_DATA] != ELFDATA2LSB) {
		std::cerr << "only little endian elf files are supported\n";
		return;
	}

	if (header_.e_ident[EI_OSABI] != ELFOSABI_SYSV) {
		std::cerr << "only sysv abi elf files are supported\n";
		return;
	}

	if (header_.e_type != ET_EXEC) {
		std::cerr << "only executable elf files are supported\n";
		return;
	}

	if (header_.e_machine != 0xF3) {
		std::cerr << "only risc-v elf files are supported\n";
		return;
	}

	section_headers_.resize(header_.e_shnum);
	memcpy(section_headers_.data(), data_ + header_.e_shoff, section_headers_.size() * sizeof(Elf32_Shdr));

	for (auto const &section : section_headers_) {
		section_map_[get_section_name(section.sh_name)] = &section;
	}

	const Span debug_str      = get_section(".debug_str");
	const Span debug_line_str = get_section(".debug_line_str");

	const Span debug_line = get_section(".debug_line");
	uint8_t *cur = debug_line.data;

	uint32_t unit_length;
	memcpy(&unit_length, cur, sizeof(unit_length));
	cur += sizeof(unit_length);
	uint8_t *line_table_program_end = cur + unit_length;

	uint16_t version;
	memcpy(&version, cur, sizeof(version));
	cur += sizeof(version);
	if (version != 5) {
		std::cerr << "only dwarf v5 is supported\n";
		return;
	}

	cur += sizeof(uint8_t); // skip address_size
	cur += sizeof(uint8_t); // skip segment_selector_size

	uint32_t header_length;
	memcpy(&header_length, cur, sizeof(header_length));
	cur += sizeof(header_length);
	line_table_program_      = cur + header_length;
	line_table_program_size_ = line_table_program_end - line_table_program_;

	cur += sizeof(uint8_t); // skip minimum_instruction_length
	cur += sizeof(uint8_t); // skip maximum_operations_per_instruction

	uint8_t opcode_base;
	memcpy(&program_header_, cur, sizeof(program_header_));
	memcpy(&opcode_base, cur + 3, sizeof(opcode_base));
	cur += sizeof(program_header_);

	for (uint8_t i = 0; i < opcode_base - 1; ++i) {
		cur = skip_leb(cur); // skip standard_opcode_lengths
	}

	uint8_t directory_entry_format_count;
	memcpy(&directory_entry_format_count, cur, sizeof(directory_entry_format_count));
	cur += sizeof(directory_entry_format_count);

	std::vector<std::pair<uint64_t, uint64_t>> directory_format;
	for (uint8_t i = 0; i < directory_entry_format_count; ++i) {
		uint64_t const content_type_code = parse_uleb(cur);
		uint64_t const form_code = parse_uleb(cur);
		directory_format.push_back({ content_type_code, form_code });
	}

	const uint64_t directories_count = parse_uleb(cur);

	std::vector<std::string> directories;
	for (uint64_t i = 0; i < directories_count; ++i) {
		std::string dir;
		for (auto const &entry : directory_format) {
			auto const [content_type_code, form_code] = entry;
			switch (content_type_code) {
				case DW_LNCT_path: {
					dir = parse_string(cur, form_code, debug_str.data, debug_line_str.data);
				} break;
				case DW_LNCT_directory_index: {
					parse_unsigned(cur, form_code);
				} break;
				case DW_LNCT_timestamp: {
					parse_unsigned(cur, form_code);
				} break;
				case DW_LNCT_size: {
					parse_unsigned(cur, form_code);
				} break;
				case DW_LNCT_MD5: {
					cur = skip_data16(cur);
				} break;
				default: {
					std::cerr << "unknown content type code " << content_type_code << '\n';
					return;
				}
			}
		}
		directories.push_back(dir);
	}

	uint8_t file_name_entry_format_count;
	memcpy(&file_name_entry_format_count, cur, sizeof(file_name_entry_format_count));
	cur += sizeof(file_name_entry_format_count);

	std::vector<std::pair<uint64_t, uint64_t>> file_name_format;
	for (uint8_t i = 0; i < file_name_entry_format_count; ++i) {
		uint64_t const content_type_code = parse_uleb(cur);
		uint64_t const form_code = parse_uleb(cur);
		file_name_format.push_back({ content_type_code, form_code });
	}

	const uint64_t file_names_count = parse_uleb(cur);

	for (uint64_t i = 0; i < file_names_count; ++i) {
		std::string file_name;
		for (auto const &entry : file_name_format) {
			auto const [content_type_code, form_code] = entry;
			switch (content_type_code) {
				case DW_LNCT_path: {
					file_name = file_name + parse_string(cur, form_code, debug_str.data, debug_line_str.data);
				} break;
				case DW_LNCT_directory_index: {
					uint64_t const directory_index = parse_unsigned(cur, form_code);
					file_name = directories[directory_index] + file_name;
				} break;
				case DW_LNCT_timestamp: {
					parse_unsigned(cur, form_code);
				} break;
				case DW_LNCT_size: {
					parse_unsigned(cur, form_code);
				} break;
				case DW_LNCT_MD5: {
					cur = skip_data16(cur);
				} break;
				default: {
					std::cerr << "unknown content type code " << content_type_code << '\n';
					return;
				}
			}
		}
		file_names_.push_back(file_name);
	}

	valid_ = true;
}

ElfFile::~ElfFile() {
	if (data_) {
		munmap(data_, file_size_);
	}
	if (fd_ >= 0) {
		close(fd_);
	}
}

Span ElfFile::text(size_t start, size_t end) {
	for (Elf32_Shdr const &section_header : section_headers_) {
		if (start >= section_header.sh_addr && end <= section_header.sh_addr + section_header.sh_size) {
			return {
				data_ + section_header.sh_offset + start - section_header.sh_addr,
				end - start
			};
		}
	}
	return { };
}

std::string ElfFile::get_string(size_t index) {
	auto const *strtab = section_map_[".strtab"];
	return std::string((char *)data_ + strtab->sh_offset + index);
}

std::string ElfFile::get_section_name(size_t index) {
	auto &section = section_headers_[header_.e_shstrndx];
	return std::string((char *)data_ + section.sh_offset + index);
}

Span ElfFile::get_section(std::string const &section_name) {
	if (section_map_.find(section_name) != section_map_.end()) {
		auto const *section = section_map_[section_name];
		return Span { data_ + section->sh_offset, section->sh_size };
	} else {
		return Span { nullptr, 0 };
	}
}
