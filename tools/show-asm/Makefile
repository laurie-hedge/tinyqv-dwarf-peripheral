INCLUDES = elf_file.h dwarf.h sim.h \
           riscv-disassembler/src/riscv-disas.h

SOURCES = ../../src/tqvp_laurie_dwarf_line_table_accelerator.sv \
		  riscv-disassembler/src/riscv-disas.c \
          main.cpp elf_file.cpp sim.cpp disasm.cpp

obj_dir/show-asm: $(SOURCES) $(INCLUDES)
	verilator -cc -CFLAGS "-g" -exe --build --trace -j 8 -o show-asm -Wall $(SOURCES)

.PHONY: clean
clean:
	rm -rf obj_dir
