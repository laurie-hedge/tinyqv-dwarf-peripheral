INCLUDES = testgen.h testbench.h test.h sim.h

SOURCES = ../src/tqvp_laurie_dwarf_line_table_accelerator.sv \
         main.cpp testgen.cpp testbench.cpp test.cpp sim.cpp

obj_dir/testbench: $(SOURCES) $(INCLUDES)
	verilator -cc -CFLAGS "-g" -exe --build --trace -j 8 -o testbench -Wall $(SOURCES)

.PHONY: clean
clean:
	rm -rf obj_dir
