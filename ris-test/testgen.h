#pragma once

#include <cstdint>
#include <random>
#include <memory>

#include "test.h"

class TestGenerator
{
public:
	virtual bool has_tests() = 0;
	virtual std::unique_ptr<Test> next_test() = 0;
};

class ReplayTestGenerator : public TestGenerator
{
	std::unique_ptr<Test> test;

public:
	ReplayTestGenerator(char const *test_file_name);

	bool has_tests() override;
	std::unique_ptr<Test> next_test() override;
};

class RandomTestGenerator : public TestGenerator
{
	std::random_device dev;
	std::mt19937 rng;
	std::uniform_int_distribution<std::mt19937::result_type> flag_dist;
	std::uniform_int_distribution<std::mt19937::result_type> byte_dist;
	std::uniform_int_distribution<std::mt19937::result_type> byte_dist_gt0;
	std::uniform_int_distribution<std::mt19937::result_type> type_dist;
	std::uniform_int_distribution<std::mt19937::result_type> opcode_base_high_dist;
	std::uniform_int_distribution<std::mt19937::result_type> opcode_base_low_dist;
	std::uniform_int_distribution<std::mt19937::result_type> num_instructions_dist;
	std::uniform_int_distribution<std::mt19937::result_type> leb_size_dist;
	std::uniform_int_distribution<std::mt19937::result_type> leb_dist;
	std::uniform_int_distribution<std::mt19937::result_type> illegal_ext_insn_dist;
	std::uniform_int_distribution<std::mt19937::result_type> legal_ext_insn_dist;
	std::uniform_int_distribution<std::mt19937::result_type> standard_instr_dist;
	std::uniform_int_distribution<std::mt19937::result_type> special_instr_dist;

	uint32_t tests_remaining;

public:
	RandomTestGenerator(uint32_t num_tests);

	bool has_tests() override;
	std::unique_ptr<Test> next_test() override;

private:
	std::unique_ptr<Test> generate_test();
	void add_random_instruction(Test *test, uint32_t opcode_base, bool can_have_illegal);
};
