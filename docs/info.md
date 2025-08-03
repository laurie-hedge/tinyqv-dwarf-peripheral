# DWARF Line Table Accelerator

Author: Laurie Hedge

Peripheral index: TBD

## What it does

Explain what your peripheral does and how it works

## Register map

| Address | Name              | Access | Description                                |
|---------|-------------------|--------|--------------------------------------------|
| 0x00    | PROGRAM_HEADER    | R/W    | DWARF line table program header.           |
| 0x01    | PROGRAM_CODE      | WO     | DWARF line table program code.             |
| 0x02    | AM_ADDRESS        | RO     | Abstract machine address.                  |
| 0x03    | AM_FILE_DISCRIM   | RO     | Abstract machine file, and discriminator.  |
| 0x04    | AM_LINE_COL_FLAGS | RO     | Abstract machine line, column, and flags.  |
| 0x05    | STATUS            | R/W    | Status of the peripheral.                  |
| 0x06    | INFO              | RO     | Peripheral version and DWARF file support. |

### PROGRAM_HEADER

This register should be written with the fields read from the line table program header before the program starts.

Writing this register resets the peripheral state and configures the peripheral to run the program.

Reading the register returns the fields of the currently configured program (i.e. the same values that were last written, other than the unused field which will always contain 0).

| 31:24       | 23:16      | 15:8      | 7:1    | 0               |
|-------------|------------|-----------|--------|-----------------|
| opcode_base | line_range | line_base | unused | default_is_stmt |

### PROGRAM_CODE

This register should be written with the line table program code. It can be written in 1, 2, or 4 byte chunks, but every byte written must be part of the program code (no padding) so if the program code is not a multiple of 4 bytes, the 1 or 2 byte variants must be used to write the last bytes.

### AM_ADDRESS

This register should only be read when the peripheral has raised an interrupt and set the STATUS to STATUS_EMIT_ROW.

It contains the address to be emitted for this row.

### AM_FILE_DISCRIM

This register should only be read when the peripheral has raised an interrupt and set the STATUS to STATUS_EMIT_ROW.

It contains the file and discriminator to be emitted for this row.

| 31:16         | 15:0 |
|---------------|------|
| discriminator | file |

### AM_LINE_COL_FLAGS

This register should only be read when the peripheral has raised an interrupt and set the STATUS to STATUS_EMIT_ROW.

It contains the line, column, is_stmt, basic_block, end_sequence, prologue_end, and epilogue_begin to be emitted for this row.

| 31     | 30             | 29           | 28           | 27          | 26      | 25:16  | 15:0 |
|--------|----------------|--------------|--------------|-------------|---------|--------|------|
| unused | epilogue_begin | prologue_end | end_sequence | basic_block | is_stmt | column | line |

### STATUS

This register contains the current state of the peripheral. It should generally be read after an interrupt from the peripheral to interpret it.

If the register has the value STATUS_EMIT_ROW following an interrupt, writing the register will change STATUS back to STATUS_READY (regardless of the value written) and will make the peripheral resume executing the current program. After receiving a STATUS_EMIT_ROW interrupt, the row being emitted should be read and only after should STATUS be written.

If the register has the value STATUS_BUSY following an interrupt, it means that the peripheral is processing a long running special instruction. No further writes to PROGRAM_CODE can be made, and instead software should continue to poll STATUS until it changes to STATUS_EMIT_ROW, meaning that the row is ready to read. To resume, STATUS should be written as in the case where the status code had initially been STATUS_EMIT_ROW.

If the register has the value STATUS_ILLEGAL following an interrupt, it means that the program has stopped running due to hitting an illegal instruction. Writing to STATUS after an illegal instruction will reset the state of the peripheral so that it is ready to execute code again, but the state of the abstract machine will be reset.

**Status Codes**

| Code | Name            | Description |
|------|-----------------|-------------|
| 0x00 | STATUS_READY    | Peripheral is ready to receive writes to PROGRAM_HEADER and PROGRAM_CODE. No interrupt has been raised. |
| 0x01 | STATUS_EMIT_ROW | Peripheral has raised an interrupt to indicate that a row has been emitted. Read the row from AM_ADDRESS, AM_FILE_DISCRIM, and AM_LINE_COL_FLAGS. |
| 0x02 | STATUS_BUSY     | Peripheral is busy processing instructions and cannot accept writes to PROGRAM_CODE at this time. |
| 0x03 | STATUS_ILLEGAL  | Peripheral has stopped due to hitting an illegal instruction. |

### INFO

This register contains information about the version of the hardware and the range of DWARF formats supported.

| 31:8             | 7:4               | 3:0               |
|------------------|-------------------|-------------------|
| hardware version | max dwarf version | min dwarf version |

## How to test

Tests should be run from inside a Docker container using a Docker image built from
tinyqv-dwarf-peripheral/.devcontainer/Dockerfile.

### Unit tests

The unit tests are hand written tests using the cocotb test framework, covering each instruction and various interesting cases.

To run the tests, from inside the Docker container, run
```
cd /path/to/tinyqv-dwarf-peripheral/test
make -B
```

### RIS tests

Random Instruction Sequence (RIS) tests work by generating a semi-random sequence of instructions to execute, and then running these instructions of both the peripheral (simulated by verilating the HDL) and through a simulator written in C++ which acts as a golden reference. The testbench compares the results of each to ensure they produce the same results. Since these tests are random, they will vary each time the tests are run, so are not run as part of CI.

To run these tests, from inside the Docker container, run
```
cd /path/to/tinyqv-dwarf-peripheral/ris-test
make
./obj_dir/testbench --run 100
```

This will run 100 randomly generated tests. You can change the number to run as many tests as you want. If a test fails, it will report the error and save a file called `test.bin`. This file captures the input into the specific test that failed, so that it can be replayed and debugged.

To replay a test.bin file, from the same directory as before, run
```
./obj_dir/testbench --rerun test.bin
```

To enable generation of the waves for the test, uncomment this section at the bottom of `tqvp_laurie_dwarf_line_table_accelerator.sv`.
```
// initial begin
//     $dumpfile("trace.vcd");
//     $dumpvars();
// end
```

## External hardware

No external hardware is required. The Pmod interface is unused by this peripheral.
