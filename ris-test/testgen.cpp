#include "testgen.h"

ReplayTestGenerator::ReplayTestGenerator(char const *test_file_name) {
	test = std::make_unique<Test>();
	test->load(test_file_name);
}

bool ReplayTestGenerator::has_tests() {
	return (bool)test;
}

std::unique_ptr<Test> ReplayTestGenerator::next_test() {
	std::unique_ptr<Test> t = std::move(test);
	test.reset();
	return t;
}

RandomTestGenerator::RandomTestGenerator(uint32_t num_tests) :
	rng(dev()),
	flag_dist(0, 1),
	byte_dist(0, 255),
	byte_dist_gt0(1, 255),
	type_dist(0, 15),
	opcode_base_high_dist(14, 255),
	opcode_base_low_dist(0, 12),
	num_instructions_dist(1, 1024),
	leb_size_dist(1, 5),
	leb_dist(0, 127),
	illegal_ext_insn_dist(3, 255),
	legal_ext_insn_dist(1, 3),
	standard_instr_dist(1, 12),
	special_instr_dist(13, 255) {
	tests_remaining = num_tests;
}

bool RandomTestGenerator::has_tests() {
	return tests_remaining > 0;
}

std::unique_ptr<Test> RandomTestGenerator::next_test() {
	tests_remaining -= 1;
	return generate_test();
}

std::unique_ptr<Test> RandomTestGenerator::generate_test() {
	auto test = std::make_unique<Test>();

	bool can_have_illegal = flag_dist(rng) == 1;

	test->program_header |= flag_dist(rng);             // default_is_stmt
	test->program_header |= (byte_dist(rng) << 8);      // line_base
	test->program_header |= (byte_dist_gt0(rng) << 16); // line_range
	auto opcode_base_type = type_dist(rng);
	uint32_t opcode_base;
	if (opcode_base_type == 0) {
		opcode_base = opcode_base_high_dist(rng);
	} else if (opcode_base_type == 1) {
		opcode_base = opcode_base_low_dist(rng);
	} else {
		opcode_base = 0x0D;
	}
	test->program_header |= (opcode_base << 24);

	uint32_t num_instructions = num_instructions_dist(rng);
	for (uint32_t i = 0; i < num_instructions - 1; ++i) {
		add_random_instruction(test.get(), opcode_base, can_have_illegal);
	}
	test->program.push_back(0);
	test->program.push_back(1);
	test->program.push_back(1);

	return test;
}

void RandomTestGenerator::add_random_instruction(Test *test, uint32_t opcode_base, bool can_have_illegal) {
	auto instruction_type = type_dist(rng);
	
	if (instruction_type < 2) {
		test->program.push_back(0);
		auto is_illegal = can_have_illegal && byte_dist(rng) == 0;
		if (is_illegal) {
			auto leb_size = leb_size_dist(rng);
			for (int i = 0; i < leb_size; ++i) {
				uint32_t leb_byte = leb_dist(rng);
				if (i+1 < leb_size) {
					leb_byte |= 0x80;
				}
				test->program.push_back(leb_byte);
			}
			uint32_t illegal_ext_insn = illegal_ext_insn_dist(rng);
			if (illegal_ext_insn == 4) {
				illegal_ext_insn = 0;
			}
			test->program.push_back(illegal_ext_insn);
		} else {
			uint32_t legal_ext_insn = legal_ext_insn_dist(rng);
			if (legal_ext_insn == 3) {
				legal_ext_insn = 4;
			}
			auto leb_size = leb_size_dist(rng);
			if (legal_ext_insn == 1) {
				test->program.push_back(0x01);
			} else if (legal_ext_insn == 2) {
				test->program.push_back(0x05);
			} else if (legal_ext_insn == 4) {
				test->program.push_back(leb_size);
			}
			test->program.push_back(legal_ext_insn);
			if (legal_ext_insn == 2) {
				for (int i = 0; i < 4; ++i) {
					test->program.push_back(byte_dist(rng));
				}
			} else if (legal_ext_insn == 4) {
				for (int i = 0; i < leb_size; ++i) {
					uint32_t leb_byte = leb_dist(rng);
					if (i+1 < leb_size) {
						leb_byte |= 0x80;
					}
					test->program.push_back(leb_byte);
				}
			}
		}
	} else if (instruction_type < 9) {
		uint32_t standard_instruction = standard_instr_dist(rng);
		test->program.push_back(standard_instruction);
		if (standard_instruction == 2 || standard_instruction == 3 || standard_instruction == 4 ||
			standard_instruction == 5 || standard_instruction == 0xc) {
			auto leb_size = leb_size_dist(rng);
			for (int i = 0; i < leb_size; ++i) {
				uint32_t leb_byte = leb_dist(rng);
				if (i+1 < leb_size) {
					leb_byte |= 0x80;
				}
				test->program.push_back(leb_byte);
			}
		} else if (standard_instruction == 9) {
			for (int i = 0; i < 2; ++i) {
				test->program.push_back(byte_dist(rng));
			}
		}
	} else {
		uint32_t special_instruction = special_instr_dist(rng);
		if (can_have_illegal || special_instruction >= opcode_base) {
			test->program.push_back(special_instruction);
		}
	}
}
