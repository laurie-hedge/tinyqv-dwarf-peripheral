#include <cstdint>
#include <iostream>
#include <memory>

#include "testgen.h"
#include "testbench.h"

struct Config
{
	char const *rerun_test_file;
	uint32_t num_tests;
};

Config parse_arguments(int argc, char **argv) {
	if (argc == 3) {
		if (strcmp(argv[1], "--rerun") == 0) {
			return { argv[2], 1 };
		} else if (strcmp(argv[1], "--run") == 0) {
			int num_tests = std::atoi(argv[2]);
			if (num_tests > 0) {
				return { nullptr, (uint32_t)num_tests };
			}
		}
	}

	std::cout << "usage: testbench [--rerun <test-file>] [--run <num-tests>]\n";
	exit(-1);
	return { };
}

int main(int argc, char **argv) {
	Config config = parse_arguments(argc, argv);

	std::unique_ptr<TestGenerator> test_generator;
	if (config.rerun_test_file) {
		test_generator = std::make_unique<ReplayTestGenerator>(config.rerun_test_file);
	} else {
		test_generator = std::make_unique<RandomTestGenerator>(config.num_tests);
	}

	Testbench testbench;

	uint32_t test_count = 0;
	while (test_generator->has_tests()) {
		std::cout << "running test " << ++test_count << "...";
		std::unique_ptr<Test> test = test_generator->next_test();
		bool passed = testbench.run_test(test.get());
		if (passed) {
			std::cout << " passed\n";
		} else {
			std::cout << "TEST FAILED\n";
			if (config.rerun_test_file == nullptr) {
				test->save("test.bin");
			}
			return -1;
		}
	}

	std::cout << "ALL TESTS PASSED\n";

	return 0;
}
