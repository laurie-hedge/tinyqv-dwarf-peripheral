#pragma once

#include "sim.h"

class Test;

class Testbench
{
	SoftwareSim swsim;
	HardwareSim hwsim;

public:
	bool run_test(Test *test);

private:
	bool compare_state();
};
