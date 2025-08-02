/*
 * Copyright (c) 2025 Laurie Hedge
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tqvp_laurie_dwarf_line_table_accelerator(
    // Clock and reset.
    input         clk,
    input         rst_n,

    // Pmod interface, unused.
    input  [7:0]  ui_in,
    output [7:0]  uo_out,

    // Register IO from TinyQV core.
    input  [5:0]  address,
    input  [31:0] data_in,
    input  [1:0]  data_write_n,
    input  [1:0]  data_read_n,
    output [31:0] data_out,
    output        data_ready,

    // Interrupt request to TinyQV core.
    output        user_interrupt
);
    // REGISTER READ/WRITE CONTROL VALUES
    // Register read/write control values used by data_write_n and data_read_n on the interface, and
    // by st_program_code_valid internally. Defined by TinyQV SPI spec.

    localparam RW_8_BIT  = 2'h0;
    localparam RW_16_BIT = 2'h1;
    localparam RW_32_BIT = 2'h2;
    localparam RW_NONE   = 2'h3;

    // MEMORY MAPPED REGISTER ADDRESSES
    // Public interface to memory mapped registers provided by the peripheral. Defined by the spec
    // for this peripheral.

    localparam PROGRAM_HEADER    = 6'h0;
    localparam PROGRAM_CODE      = 6'h1;
    localparam AM_ADDRESS        = 6'h2;
    localparam AM_FILE_DISCRIM   = 6'h3;
    localparam AM_LINE_COL_FLAGS = 6'h4;
    localparam STATUS            = 6'h5;
    localparam INFO              = 6'h6;

    // PERIPHERAL STATUS CODES
    // Public interface, values read by software from the STATUS register. Defined by the spec for
    // this peripheral.
    localparam STATUS_READY    = 2'h0;
    localparam STATUS_EMIT_ROW = 2'h1;
    localparam STATUS_BUSY     = 2'h2;

    // DWARF STANDARD OPCODES
    // The DWARF line table standard opcodes. Defined by the DWARF v5 spec.

    localparam DW_LNS_COPY             = 8'h01;
    localparam DW_LNS_ADVANCEPC        = 8'h02;
    localparam DW_LNS_ADVANCELINE      = 8'h03;
    localparam DW_LNS_SETFILE          = 8'h04;
    localparam DW_LNS_SETCOLUMN        = 8'h05;
    localparam DW_LNS_NEGATESTMT       = 8'h06;
    localparam DW_LNS_SETBASICBLOCK    = 8'h07;
    localparam DW_LNS_CONSTADDPC       = 8'h08;
    localparam DW_LNS_FIXEDADVANCEPC   = 8'h09;
    localparam DW_LNS_SETPROLOGUEEND   = 8'h0A;
    localparam DW_LNS_SETEPILOGUEBEGIN = 8'h0B;
    localparam DW_LNS_SETISA           = 8'h0C;

    // DWARF EXTENDED OPCODES
    // The DWARF line table extended opcodes. Defined by the DWARF v5 spec.

    localparam EXTENDED_OPCODE_START   = 8'h00;
    localparam DW_LNE_ENDSEQUENCE      = 8'h01;
    localparam DW_LNE_SETADDRESS       = 8'h02;
    localparam DW_LNE_SETDISCRIMINATOR = 8'h04;

    // STATE MACHINE
    // The state machine controls the operation of the peripheral. The state determines which
    // operation is performed this cycle, and is only changed on the rising edge of the clock. This
    // logic is responsible for managing state transitions.

    enum logic[4:0] {
        STATE_READY,
        STATE_EXTENDED_OPCODE,
        STATE_SPECIAL_OPCODE,
        STATE_PAUSE_FOR_COPY,
        STATE_PAUSE_FOR_END_SEQUENCE,
        STATE_PARSE_LEB_128_BYTE0,
        STATE_PARSE_LEB_128_BYTE1,
        STATE_PARSE_LEB_128_BYTE2,
        STATE_PARSE_LEB_128_BYTE3,
        STATE_PARSE_LEB_128_OVERFLOW,
        STATE_PARSE_U16_BYTE0,
        STATE_PARSE_U16_BYTE1,
        STATE_PARSE_U64_BYTE0,
        STATE_PARSE_U64_BYTE1,
        STATE_PARSE_U64_BYTE2,
        STATE_PARSE_U64_BYTE3,
        STATE_PARSE_U64_BYTE4,
        STATE_PARSE_U64_BYTE5,
        STATE_PARSE_U64_BYTE6,
        STATE_PARSE_U64_BYTE7,
        STATE_EXEC
    } st_state;

    always_ff @(posedge clk) begin
        if      (set_st_state_ready)                  st_state <= STATE_READY;
        else if (set_st_state_extended_opcode)        st_state <= STATE_EXTENDED_OPCODE;
        else if (set_st_state_special_opcode)         st_state <= STATE_SPECIAL_OPCODE;
        else if (set_st_state_pause_for_copy)         st_state <= STATE_PAUSE_FOR_COPY;
        else if (set_st_state_pause_for_end_sequence) st_state <= STATE_PAUSE_FOR_END_SEQUENCE;
        else if (set_st_state_parse_leb_128_byte0)    st_state <= STATE_PARSE_LEB_128_BYTE0;
        else if (set_st_state_parse_leb_128_byte1)    st_state <= STATE_PARSE_LEB_128_BYTE1;
        else if (set_st_state_parse_leb_128_byte2)    st_state <= STATE_PARSE_LEB_128_BYTE2;
        else if (set_st_state_parse_leb_128_byte3)    st_state <= STATE_PARSE_LEB_128_BYTE3;
        else if (set_st_state_parse_leb_128_overflow) st_state <= STATE_PARSE_LEB_128_OVERFLOW;
        else if (set_st_state_parse_u16_byte0)        st_state <= STATE_PARSE_U16_BYTE0;
        else if (set_st_state_parse_u16_byte1)        st_state <= STATE_PARSE_U16_BYTE1;
        else if (set_st_state_parse_u64_byte0)        st_state <= STATE_PARSE_U64_BYTE0;
        else if (set_st_state_parse_u64_byte1)        st_state <= STATE_PARSE_U64_BYTE1;
        else if (set_st_state_parse_u64_byte2)        st_state <= STATE_PARSE_U64_BYTE2;
        else if (set_st_state_parse_u64_byte3)        st_state <= STATE_PARSE_U64_BYTE3;
        else if (set_st_state_parse_u64_byte4)        st_state <= STATE_PARSE_U64_BYTE4;
        else if (set_st_state_parse_u64_byte5)        st_state <= STATE_PARSE_U64_BYTE5;
        else if (set_st_state_parse_u64_byte6)        st_state <= STATE_PARSE_U64_BYTE6;
        else if (set_st_state_parse_u64_byte7)        st_state <= STATE_PARSE_U64_BYTE7;
        else if (set_st_state_exec)                   st_state <= STATE_EXEC;
    end

    logic reset_this_cycle;
    logic write_this_cycle;
    logic exec_current_instruction_this_cycle;
    logic special_opcode_this_cycle;
    logic special_opcode_end_this_cycle;
    logic parse_byte_this_cycle;
    logic parse_extended_opcode_this_cycle;
    logic parse_standard_opcode_this_cycle;
    logic parse_special_opcode_this_cycle;
    logic parse_standard_or_special_opcode_this_cycle;
    logic parse_special_opcode_or_constaddpc_this_cycle;
    logic execution_paused;
    logic write_status;

    assign reset_this_cycle = !rst_n;

    assign write_this_cycle =
        !reset_this_cycle && data_write_n != RW_NONE;

    assign exec_current_instruction_this_cycle =
        !reset_this_cycle && !write_this_cycle && st_state == STATE_EXEC;

    assign special_opcode_this_cycle =
        !reset_this_cycle && !write_this_cycle && st_state == STATE_SPECIAL_OPCODE;

    assign special_opcode_end_this_cycle =
        special_opcode_this_cycle && st_operand[7:0] < ph_line_range;

    assign parse_byte_this_cycle =
        !reset_this_cycle && !write_this_cycle && !exec_current_instruction_this_cycle &&
        !special_opcode_this_cycle && !execution_paused && current_byte_valid;

    assign parse_extended_opcode_this_cycle =
        parse_byte_this_cycle && st_state == STATE_EXTENDED_OPCODE;

    assign parse_standard_or_special_opcode_this_cycle =
        parse_byte_this_cycle && st_state == STATE_READY;

    assign parse_standard_opcode_this_cycle =
        parse_standard_or_special_opcode_this_cycle && current_byte < ph_opcode_base;

    assign parse_special_opcode_this_cycle =
        parse_standard_or_special_opcode_this_cycle && !parse_standard_opcode_this_cycle;

    assign parse_special_opcode_or_constaddpc_this_cycle =
        parse_special_opcode_this_cycle ||
        (parse_standard_opcode_this_cycle && current_byte == DW_LNS_CONSTADDPC);

    assign execution_paused =
        st_state == STATE_PAUSE_FOR_COPY || st_state == STATE_PAUSE_FOR_END_SEQUENCE;

    assign write_status = write_this_cycle && address == STATUS;

    logic set_st_state_ready;
    logic set_st_state_extended_opcode;
    logic set_st_state_special_opcode;
    logic set_st_state_pause_for_copy;
    logic set_st_state_pause_for_end_sequence;
    logic set_st_state_parse_leb_128_byte0;
    logic set_st_state_parse_leb_128_byte1;
    logic set_st_state_parse_leb_128_byte2;
    logic set_st_state_parse_leb_128_byte3;
    logic set_st_state_parse_leb_128_overflow;
    logic set_st_state_parse_u16_byte0;
    logic set_st_state_parse_u16_byte1;
    logic set_st_state_parse_u64_byte0;
    logic set_st_state_parse_u64_byte1;
    logic set_st_state_parse_u64_byte2;
    logic set_st_state_parse_u64_byte3;
    logic set_st_state_parse_u64_byte4;
    logic set_st_state_parse_u64_byte5;
    logic set_st_state_parse_u64_byte6;
    logic set_st_state_parse_u64_byte7;
    logic set_st_state_exec;

    assign set_st_state_ready =
        reset_this_cycle || write_program_header || write_status ||
        (special_opcode_end_this_cycle && st_current_instruction == INSTR_CONSTADDPC) ||
        (exec_current_instruction_this_cycle && st_current_instruction != INSTR_EXTENDED);

    assign set_st_state_extended_opcode =
        exec_current_instruction_this_cycle && st_current_instruction == INSTR_EXTENDED;

    assign set_st_state_special_opcode =
        parse_special_opcode_or_constaddpc_this_cycle ||
        (st_state == STATE_SPECIAL_OPCODE && !special_opcode_end_this_cycle);

    assign set_st_state_pause_for_copy =
        (parse_standard_or_special_opcode_this_cycle && current_byte == DW_LNS_COPY) ||
        (special_opcode_end_this_cycle && st_current_instruction == INSTR_NOP);

    assign set_st_state_pause_for_end_sequence =
        parse_extended_opcode_this_cycle && current_byte == DW_LNE_ENDSEQUENCE;

    assign set_st_state_parse_leb_128_byte0 =
        (parse_extended_opcode_this_cycle && current_byte == DW_LNE_SETDISCRIMINATOR) ||
        (parse_standard_opcode_this_cycle && (
            current_byte == DW_LNS_ADVANCEPC || current_byte == DW_LNS_ADVANCELINE ||
            current_byte == DW_LNS_SETFILE || current_byte == DW_LNS_SETCOLUMN ||
            current_byte == DW_LNS_SETISA || current_byte == EXTENDED_OPCODE_START));

    assign set_st_state_parse_leb_128_byte1 =
        parse_byte_this_cycle && st_state == STATE_PARSE_LEB_128_BYTE0 && !leb_last_byte;

    assign set_st_state_parse_leb_128_byte2 =
        parse_byte_this_cycle && st_state == STATE_PARSE_LEB_128_BYTE1 && !leb_last_byte;

    assign set_st_state_parse_leb_128_byte3 =
        parse_byte_this_cycle && !leb_last_byte && st_state == STATE_PARSE_LEB_128_BYTE2;

    assign set_st_state_parse_leb_128_overflow =
        parse_byte_this_cycle && !leb_last_byte &&
        (st_state == STATE_PARSE_LEB_128_BYTE3 || st_state == STATE_PARSE_LEB_128_OVERFLOW);

    assign set_st_state_parse_u16_byte0 =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_FIXEDADVANCEPC;

    assign set_st_state_parse_u16_byte1 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U16_BYTE0;

    assign set_st_state_parse_u64_byte0 =
        parse_extended_opcode_this_cycle && current_byte == DW_LNE_SETADDRESS;

    assign set_st_state_parse_u64_byte1 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE0;

    assign set_st_state_parse_u64_byte2 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE1;

    assign set_st_state_parse_u64_byte3 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE2;

    assign set_st_state_parse_u64_byte4 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE3;

    assign set_st_state_parse_u64_byte5 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE4;

    assign set_st_state_parse_u64_byte6 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE5;

    assign set_st_state_parse_u64_byte7 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE6;

    assign set_st_state_exec =
        parse_byte_this_cycle && (
            (leb_last_byte && (
                st_state == STATE_PARSE_LEB_128_BYTE0 || st_state == STATE_PARSE_LEB_128_BYTE1 ||
                st_state == STATE_PARSE_LEB_128_BYTE2 || st_state == STATE_PARSE_LEB_128_BYTE3 ||
                st_state == STATE_PARSE_LEB_128_OVERFLOW)
            ) || st_state == STATE_PARSE_U16_BYTE1 || st_state == STATE_PARSE_U64_BYTE7);

    // CURRENT INSTRUCTION
    // Instructions with operands and extended instructions cannot be executed on their first byte,
    // so the decoded instruction is stored as the current instruction to be executed when parsing
    // the operands is complete. This logic manages the state of the current instruction.

    enum logic[3:0] {
        INSTR_NOP,
        INSTR_ADVANCEPC,
        INSTR_ADVANCELINE,
        INSTR_SETFILE,
        INSTR_SETCOLUMN,
        INSTR_CONSTADDPC,
        INSTR_EXTENDED,
        INSTR_SETADDRESS,
        INSTR_SETDISCRIMINATOR
    } st_current_instruction;

    always_ff @(posedge clk) begin
        if      (set_current_instruction_nop)
            st_current_instruction <= INSTR_NOP;
        else if (set_current_instruction_advancepc)
            st_current_instruction <= INSTR_ADVANCEPC;
        else if (set_current_instruction_advanceline)
            st_current_instruction <= INSTR_ADVANCELINE;
        else if (set_current_instruction_setfile)
            st_current_instruction <= INSTR_SETFILE;
        else if (set_current_instruction_setcolumn)
            st_current_instruction <= INSTR_SETCOLUMN;
        else if (set_current_instruction_setconstaddpc)
            st_current_instruction <= INSTR_CONSTADDPC;
        else if (set_current_instruction_extended)
            st_current_instruction <= INSTR_EXTENDED;
        else if (set_current_instruction_setaddress)
            st_current_instruction <= INSTR_SETADDRESS;
        else if (set_current_instruction_setdiscriminator)
            st_current_instruction <= INSTR_SETDISCRIMINATOR;
    end

    logic set_current_instruction_nop;
    logic set_current_instruction_advancepc;
    logic set_current_instruction_advanceline;
    logic set_current_instruction_setfile;
    logic set_current_instruction_setcolumn;
    logic set_current_instruction_setconstaddpc;
    logic set_current_instruction_extended;
    logic set_current_instruction_setaddress;
    logic set_current_instruction_setdiscriminator;

    assign set_current_instruction_nop =
        reset_this_cycle || write_program_header || write_status ||
        (parse_standard_opcode_this_cycle && current_byte == DW_LNS_SETISA) ||
        parse_special_opcode_this_cycle;

    assign set_current_instruction_advancepc =
        parse_standard_opcode_this_cycle &&
        (current_byte == DW_LNS_ADVANCEPC || current_byte == DW_LNS_FIXEDADVANCEPC);

    assign set_current_instruction_advanceline =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_ADVANCELINE;

    assign set_current_instruction_setfile =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_SETFILE;

    assign set_current_instruction_setcolumn =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_SETCOLUMN;

    assign set_current_instruction_setconstaddpc =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_CONSTADDPC;

    assign set_current_instruction_extended =
        parse_standard_opcode_this_cycle && current_byte == EXTENDED_OPCODE_START;

    assign set_current_instruction_setaddress =
        parse_extended_opcode_this_cycle && current_byte == DW_LNE_SETADDRESS;

    assign set_current_instruction_setdiscriminator =
        parse_extended_opcode_this_cycle && current_byte == DW_LNE_SETDISCRIMINATOR;

    // LEB SIGNED
    // When parsing an LEB encoded number, this records whether the number is signed, and therefore
    // controls whether the number should be sign-extended.

    logic st_leb_signed;

    logic unset_leb_signed;
    logic set_leb_signed;

    assign unset_leb_signed =
        reset_this_cycle || write_program_header || write_status ||
        (parse_standard_opcode_this_cycle && (
            current_byte == DW_LNS_ADVANCEPC || current_byte == DW_LNS_SETFILE ||
            current_byte == DW_LNS_SETCOLUMN || current_byte == DW_LNS_SETISA ||
            current_byte == EXTENDED_OPCODE_START)) ||
        (parse_extended_opcode_this_cycle && current_byte == DW_LNE_SETDISCRIMINATOR);

    assign set_leb_signed =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_ADVANCELINE;

    always_ff @(posedge clk) begin
        if      (unset_leb_signed) st_leb_signed <= 0;
        else if (set_leb_signed)   st_leb_signed <= 1;
    end

    // INSTRUCTION POINTER
    // Pointer to the byte index in the code buffer of the next byte to process. Although there are
    // only four bytes in the buffer, this must be able to represent one off the end to indicate
    // that all the bytes have been processed, which is why this must be three bits rather than
    // just two.

    logic [2:0] st_ip;

    always_ff @(posedge clk) begin
        if      (reset_st_ip)           st_ip <= 3'h0;
        else if (parse_byte_this_cycle) st_ip <= incrementer_dest;
    end

    logic reset_st_ip;

    assign reset_st_ip = reset_this_cycle || write_program_header || write_program_code;

    // PROGRAM HEADER
    // Some parts of the DWARF line table program header have an impact on execution. These parts
    // are passed in to the accelerator through the PROGRAM_HEADER memory mapped register.

    logic ph_default_is_stmt;

    always_ff @(posedge clk) begin
        if      (reset_this_cycle)     ph_default_is_stmt <= 0;
        else if (write_program_header) ph_default_is_stmt <= data_in[0];
    end

    logic [7:0] ph_line_base;

    always_ff @(posedge clk) begin
        if      (reset_this_cycle)           ph_line_base <= 8'h0;
        else if (write_program_header_byte1) ph_line_base <= data_in[15:8];
    end

    logic [7:0] ph_line_range;

    always_ff @(posedge clk) begin
        if      (reset_this_cycle)                 ph_line_range <= 8'h0;
        else if (write_program_header_byte2_byte3) ph_line_range <= data_in[23:16];
    end

    logic [7:0] ph_opcode_base;

    always_ff @(posedge clk) begin
        if      (reset_this_cycle)                 ph_opcode_base <= 8'h0;
        else if (write_program_header_byte2_byte3) ph_opcode_base <= data_in[31:24];
    end

    logic write_program_header;
    logic write_program_header_byte1;
    logic write_program_header_byte2_byte3;

    assign write_program_header = write_this_cycle && address == PROGRAM_HEADER;

    assign write_program_header_byte1 = write_program_header && data_write_n[1] != data_write_n[0];

    assign write_program_header_byte2_byte3 = write_program_header && data_write_n == RW_32_BIT;

    // PROGRAM CODE
    // Program code can be written by the host CPU in groups of 1, 2 or 4 bytes. These are stored in
    // the program code buffer, and which bytes have been written are recorded in the program code
    // buffer valid, in the same format as the read and write flags from the interface. Each write
    // completely overwrites the buffer. Generally the accelerator can parse one byte per cycle.
    // Since writes can occur no more often than once every 8 cycles, it is generally fine since
    // the whole buffer should already have been processed. In cases where this is not the case,
    // such as long-running special instructions, the host must be interrupted so that it knows to
    // stall until the accelerator is ready. If the host ignores this, the program code will be
    // corrupted.

    logic [1:0]  st_program_code_valid;

    always_ff @(posedge clk) begin
        if      (reset_st_program_code) st_program_code_valid <= RW_NONE;
        else if (write_program_code)    st_program_code_valid <= data_write_n;
    end

    logic [31:0] st_program_code_buffer;

    always_ff @(posedge clk) begin
        if      (reset_st_program_code)         st_program_code_buffer <= 32'h0;
        else if (write_program_code_one_byte)   st_program_code_buffer <= { 24'h0, data_in[7:0] };
        else if (write_program_code_two_bytes)  st_program_code_buffer <= { 16'h0, data_in[15:0] };
        else if (write_program_code_four_bytes) st_program_code_buffer <= data_in;
    end

    logic reset_st_program_code;
    logic write_program_code;
    logic write_program_code_one_byte;
    logic write_program_code_two_bytes;
    logic write_program_code_four_bytes;

    assign reset_st_program_code = reset_this_cycle || write_program_header;

    assign write_program_code = write_this_cycle && address == PROGRAM_CODE;

    assign write_program_code_one_byte = write_program_code && data_write_n == RW_8_BIT;

    assign write_program_code_two_bytes = write_program_code && data_write_n == RW_16_BIT;

    assign write_program_code_four_bytes = write_program_code && data_write_n == RW_32_BIT;

    // CURRENT BYTE
    // The accelerator processes one byte per cycle. The current byte is the value of the byte
    // pointed to by the instruction pointer in the program buffer, or 0 if the instruction pointer
    // is off the end of the buffer. This does not consider whether or not the byte is actually
    // valid.

    logic [7:0] current_byte;

    always_comb begin
        case (st_ip)
            3'h0:    current_byte = st_program_code_buffer[7:0];
            3'h1:    current_byte = st_program_code_buffer[15:8];
            3'h2:    current_byte = st_program_code_buffer[23:16];
            3'h3:    current_byte = st_program_code_buffer[31:24];
            default: current_byte = 8'h0;
        endcase
    end

    logic leb_last_byte;

    assign leb_last_byte = current_byte[7] == 0;

    // CURRENT BYTE VALID
    // The current byte always points to the byte referenced by the instruction pointer, but it is
    // not always valid. The current byte valid flag indicates if the byte is valid and can be used
    // this cycle.

    logic current_byte_valid;

    always_comb begin
        case (st_ip)
            3'h0:    current_byte_valid = st_program_code_valid != RW_NONE;
            3'h1:    current_byte_valid = st_program_code_valid[0] != st_program_code_valid[1];
            3'h2:    current_byte_valid = st_program_code_valid == RW_32_BIT;
            3'h3:    current_byte_valid = st_program_code_valid == RW_32_BIT;
            default: current_byte_valid = 0;
        endcase
    end

    // OPERAND
    // Opcodes may have a single operand. This operand may be constructed over multiple cycles since
    // operands can be multiple bytes, and the accelerator only parses one byte per cycle. Only 28
    // bits are needed since none of the registers are any larger than that, so any larger values
    // would overflow anyway and so can be safely discarded.

    logic [27:0] st_operand;

    always_ff @(posedge clk) begin
        if (reset_st_operand)
            st_operand <= 28'h0;
        else if (set_st_operand_from_byte_subtractor)
            st_operand <= byte_subtractor_dest_zero_extended;
        else if (parse_leb_128_byte0)
            st_operand <= {
                st_leb_signed ? { 21{ current_byte[6] } } : 21'h0,
                current_byte[6:0]
            };
        else if (parse_leb_128_byte1)
            st_operand <= {
                st_leb_signed ? { 14{ current_byte[6] } } : 14'h0,
                current_byte[6:0],
                st_operand[6:0]
            };
        else if (parse_leb_128_byte2)
            st_operand <= {
                st_leb_signed ? { 7{ current_byte[6] } } : 7'h0,
                current_byte[6:0],
                st_operand[13:0]
            };
        else if (parse_leb_128_byte3)
            st_operand <= { current_byte[6:0], st_operand[20:0] };
        else if (parse_uint_byte0)
            st_operand <= { 20'h0, current_byte[7:0] };
        else if (parse_uint_byte1)
            st_operand <= { 12'h0, current_byte[7:0], st_operand[7:0] };
        else if (parse_uint_byte2)
            st_operand <= { 4'h0, current_byte[7:0], st_operand[15:0] };
        else if (parse_uint_byte3)
            st_operand <= { current_byte[3:0], st_operand[23:0] };
    end

    logic reset_st_operand;
    logic set_st_operand_from_byte_subtractor;
    logic parse_leb_128_byte0;
    logic parse_leb_128_byte1;
    logic parse_leb_128_byte2;
    logic parse_leb_128_byte3;
    logic parse_uint_byte0;
    logic parse_uint_byte1;
    logic parse_uint_byte2;
    logic parse_uint_byte3;

    assign reset_st_operand = reset_this_cycle || write_program_header;

    assign set_st_operand_from_byte_subtractor =
        parse_special_opcode_or_constaddpc_this_cycle || special_opcode_this_cycle;

    assign parse_leb_128_byte0 =
        parse_byte_this_cycle && st_state == STATE_PARSE_LEB_128_BYTE0;

    assign parse_leb_128_byte1 =
        parse_byte_this_cycle && st_state == STATE_PARSE_LEB_128_BYTE1;

    assign parse_leb_128_byte2 =
        parse_byte_this_cycle && st_state == STATE_PARSE_LEB_128_BYTE2;

    assign parse_leb_128_byte3 =
        parse_byte_this_cycle && st_state == STATE_PARSE_LEB_128_BYTE3;

    assign parse_uint_byte0 =
        parse_byte_this_cycle &&
        (st_state == STATE_PARSE_U16_BYTE0 || st_state == STATE_PARSE_U64_BYTE0);

    assign parse_uint_byte1 =
        parse_byte_this_cycle &&
        (st_state == STATE_PARSE_U16_BYTE1 || st_state == STATE_PARSE_U64_BYTE1);

    assign parse_uint_byte2 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE2;

    assign parse_uint_byte3 =
        parse_byte_this_cycle && st_state == STATE_PARSE_U64_BYTE3;

    logic [27:0] byte_subtractor_dest_zero_extended;
    logic [7:0]  byte_subtractor_dest;
    logic [7:0]  byte_subtractor_src0;
    logic [7:0]  byte_subtractor_src1;

    assign byte_subtractor_dest_zero_extended = { 20'h0, byte_subtractor_dest };

    assign byte_subtractor_dest = byte_subtractor_src0 - byte_subtractor_src1;

    assign byte_subtractor_src0 =
        special_opcode_this_cycle       ? st_operand[7:0] :
        parse_special_opcode_this_cycle ? current_byte :
                                          28'hFF;

    assign byte_subtractor_src1 = special_opcode_this_cycle ? ph_line_range : ph_opcode_base;

    // ABSTRACT MACHINE ADDRESS
    // The abstract machine address stores the instruction pointer value calculated by the line
    // table program. It only needs to store 27 bits, since the physical address space of the
    // TinyQV core is 28 bits, and RV32EC requires that instructions be 2-byte aligned, so an odd
    // instruction pointer is illegal.

    logic [27:0] am_address;

    always_ff @(posedge clk) begin
        if      (reset_am_address)             am_address <= 28'h0;
        else if (add_operand_to_am_address)    am_address <= main_adder_dest;
        else if (assign_operand_to_am_address) am_address <= st_operand[27:0];
        else if (increment_am_address)         am_address <= incrementer_dest;
    end

    logic reset_am_address;
    logic add_operand_to_am_address;
    logic assign_operand_to_am_address;
    logic increment_am_address;

    assign reset_am_address =
        reset_this_cycle || write_program_header ||
        (write_status && st_state == STATE_PAUSE_FOR_END_SEQUENCE);

    assign add_operand_to_am_address =
        exec_current_instruction_this_cycle && st_current_instruction == INSTR_ADVANCEPC;

    assign assign_operand_to_am_address =
        exec_current_instruction_this_cycle && st_current_instruction == INSTR_SETADDRESS;

    assign increment_am_address =
        special_opcode_this_cycle && !special_opcode_end_this_cycle;

    // ABSTRACT MACHINE FILE
    // The abstract machine address stores the file index calculated by the line table program.
    // There is no fixed size that this should be, so this accelerator assumes that 16-bits should
    // be sufficient for any reasonable number of files.

    logic [15:0] am_file;

    always_ff @(posedge clk) begin
        if      (reset_am_file)             am_file <= 16'h1;
        else if (assign_operand_to_am_file) am_file <= st_operand[15:0];
    end

    logic reset_am_file;
    logic assign_operand_to_am_file;

    assign reset_am_file =
        reset_this_cycle || write_program_header ||
        (write_status && st_state == STATE_PAUSE_FOR_END_SEQUENCE);

    assign assign_operand_to_am_file =
        exec_current_instruction_this_cycle && st_current_instruction == INSTR_SETFILE;

    // ABSTRACT MACHINE LINE
    // The abstract machine address stores the line number calculated by the line table program.
    // There is no fixed size that this should be, so this accelerator assumes that 16-bits should
    // be sufficient for any reasonable number of lines.

    logic [15:0] am_line;

    always_ff @(posedge clk) begin
        if      (reset_am_line)       am_line <= 16'h1;
        else if (add_src1_to_am_line) am_line <= main_adder_dest[15:0];
    end

    logic reset_am_line;
    logic add_src1_to_am_line;

    assign reset_am_line =
        reset_this_cycle || write_program_header ||
        (write_status && st_state == STATE_PAUSE_FOR_END_SEQUENCE);

    assign add_src1_to_am_line =
        (exec_current_instruction_this_cycle && st_current_instruction == INSTR_ADVANCELINE) ||
        parse_special_opcode_or_constaddpc_this_cycle || special_opcode_end_this_cycle;

    logic [27:0] sign_extended_line_base;

    assign sign_extended_line_base = { { 21{ ph_line_base[7] } }, ph_line_base[6:0] };

    // ABSTRACT MACHINE FILE
    // The abstract machine address stores the column number calculated by the line table program.
    // There is no fixed size that this should be, so this accelerator assumes that 10-bits should
    // be sufficient for any reasonable line length.

    logic [9:0]  am_column;

    always_ff @(posedge clk) begin
        if      (reset_am_column)             am_column <= 10'h0;
        else if (assign_operand_to_am_column) am_column <= st_operand[9:0];
    end

    logic reset_am_column;
    logic assign_operand_to_am_column;

    assign reset_am_column =
        reset_this_cycle || write_program_header ||
        (write_status && st_state == STATE_PAUSE_FOR_END_SEQUENCE);

    assign assign_operand_to_am_column =
        exec_current_instruction_this_cycle && st_current_instruction == INSTR_SETCOLUMN;

    // ABSTRACT MACHINE IS STMT
    // The abstract machine flag marking the start of a statement.

    logic am_is_stmt;

    always_ff @(posedge clk) begin
        if      (reset_this_cycle)            am_is_stmt <= 0;
        else if (write_program_header)        am_is_stmt <= data_in[0];
        else if (reset_am_is_stmt_to_default) am_is_stmt <= ph_default_is_stmt;
        else if (negate_am_is_stmt)           am_is_stmt <= !am_is_stmt;
    end

    logic reset_am_is_stmt_to_default;
    logic negate_am_is_stmt;

    assign reset_am_is_stmt_to_default = write_status && st_state == STATE_PAUSE_FOR_END_SEQUENCE;

    assign negate_am_is_stmt =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_NEGATESTMT;

    // ABSTRACT MACHINE BASIC BLOCK
    // The abstract machine flag marking the start of a basic block.

    logic am_basic_block;

    always_ff @(posedge clk) begin
        if      (reset_am_basic_block) am_basic_block <= 0;
        else if (set_am_basic_block)   am_basic_block <= 1;
    end

    logic reset_am_basic_block;
    logic set_am_basic_block;

    assign reset_am_basic_block =
        reset_this_cycle || write_program_header || (write_status && execution_paused);

    assign set_am_basic_block   =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_SETBASICBLOCK;

    // ABSTRACT MACHINE END SEQUENCE
    // The abstract machine flag marking the byte after the end of a sequence of instructions.

    logic am_end_sequence;

    always_ff @(posedge clk) begin
        if      (reset_am_end_sequence) am_end_sequence <= 0;
        else if (set_am_end_sequence)   am_end_sequence <= 1;
    end

    logic reset_am_end_sequence;
    logic set_am_end_sequence;

    assign reset_am_end_sequence =
        reset_this_cycle || write_program_header ||
        (write_status && st_state == STATE_PAUSE_FOR_END_SEQUENCE);

    assign set_am_end_sequence =
        parse_extended_opcode_this_cycle && current_byte == DW_LNE_ENDSEQUENCE;

    // ABSTRACT MACHINE PROLOGUE END
    // The abstract machine flag marking the end of a function prologue.

    logic am_prologue_end;

    always_ff @(posedge clk) begin
        if      (reset_am_prologue_end) am_prologue_end <= 0;
        else if (set_am_prologue_end)   am_prologue_end <= 1;
    end

    logic reset_am_prologue_end;
    logic set_am_prologue_end;

    assign reset_am_prologue_end =
        reset_this_cycle || write_program_header || (write_status && execution_paused);

    assign set_am_prologue_end =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_SETPROLOGUEEND;

    // ABSTRACT MACHINE EPILOGUE BEGIN
    // The abstract machine flag marking the beginning of a function epilogue.

    logic am_epilogue_begin;

    always_ff @(posedge clk) begin
        if      (reset_am_epilogue_begin) am_epilogue_begin <= 0;
        else if (set_am_epilogue_begin)   am_epilogue_begin <= 1;
    end

    logic reset_am_epilogue_begin;
    logic set_am_epilogue_begin;

    assign reset_am_epilogue_begin =
        reset_this_cycle || write_program_header || (write_status && execution_paused);

    assign set_am_epilogue_begin =
        parse_standard_opcode_this_cycle && current_byte == DW_LNS_SETEPILOGUEBEGIN;

    // ABSTRACT MACHINE DISCRIMINATOR
    // The abstract machine address stores an identifier calculated by the line table program.
    // There is no fixed size that this should be, so this accelerator assumes that 16-bits should
    // be sufficient.

    logic [15:0] am_discriminator;

    always_ff @(posedge clk) begin
        if      (reset_am_discriminator)             am_discriminator <= 16'h0;
        else if (assign_operand_to_am_discriminator) am_discriminator <= st_operand[15:0];
    end

    logic reset_am_discriminator;
    logic assign_operand_to_am_discriminator;

    assign reset_am_discriminator =
        reset_this_cycle || write_program_header || (write_status && execution_paused);

    assign assign_operand_to_am_discriminator =
        exec_current_instruction_this_cycle && st_current_instruction == INSTR_SETDISCRIMINATOR;

    // STATUS REGISTER
    // This logic composes the internal state into the format of the public facing memory mapped
    // registers, and selects which if any to write back over the SPI.

    logic [1:0] out_status;

    always_ff @(posedge clk) begin
        if      (set_out_status_ready)                          out_status <= STATUS_READY;
        else if (set_out_status_emit_row)                       out_status <= STATUS_EMIT_ROW;
        else if (parse_special_opcode_or_constaddpc_this_cycle) out_status <= STATUS_BUSY;
    end

    logic set_out_status_ready;
    logic set_out_status_emit_row;

    assign set_out_status_ready =
        reset_this_cycle || write_program_header || write_status ||
        (out_status == STATUS_BUSY && st_state == STATE_READY && !current_byte_valid);

    assign set_out_status_emit_row =
        (parse_standard_opcode_this_cycle && current_byte == DW_LNS_COPY) ||
        (parse_extended_opcode_this_cycle && current_byte == DW_LNE_ENDSEQUENCE) ||
        (special_opcode_end_this_cycle && st_current_instruction == INSTR_NOP);

    // REGISTER OUTPUTS
    // This logic composes the internal state into the format of the public facing memory mapped
    // registers, and selects which if any to write back over the SPI.

    localparam VERSION_INFO = 32'h00000155;

    assign data_out[7:0]   = register_read_byte0       ? out_selected_register[7:0]   : 8'h0;
    assign data_out[15:8]  = register_read_byte1       ? out_selected_register[15:8]  : 8'h0;
    assign data_out[31:16] = register_read_byte2_byte3 ? out_selected_register[31:16] : 16'h0;
    assign data_ready      = 1;

    logic [31:0] out_selected_register;
    logic [31:0] out_program_header;
    logic [31:0] out_am_address;
    logic [31:0] out_am_file_descrim;
    logic [31:0] out_am_line_col_flags;
    logic        register_read_byte0;
    logic        register_read_byte1;
    logic        register_read_byte2_byte3;

    always_comb begin
        case (address)
            PROGRAM_HEADER:    out_selected_register = out_program_header;
            AM_ADDRESS:        out_selected_register = out_am_address;
            AM_FILE_DISCRIM:   out_selected_register = out_am_file_descrim;
            AM_LINE_COL_FLAGS: out_selected_register = out_am_line_col_flags;
            STATUS:            out_selected_register = { 31'h0, out_status };
            INFO:              out_selected_register = VERSION_INFO;
            default:           out_selected_register = 32'h0;
        endcase
    end

    assign out_program_header = {
        ph_opcode_base, ph_line_range, ph_line_base, 7'h0, ph_default_is_stmt
    };

    assign out_am_address = { 4'h0, am_address };

    assign out_am_file_descrim = { am_discriminator, am_file };

    assign out_am_line_col_flags = {
        1'h0, am_epilogue_begin, am_prologue_end, am_end_sequence, am_basic_block, am_is_stmt,
        am_column, am_line
    };

    assign register_read_byte0 = data_read_n != RW_NONE;

    assign register_read_byte1 = data_read_n[0] != data_read_n[1];

    assign register_read_byte2_byte3 = data_read_n == RW_32_BIT;

    // INTERRUPT OUTPUT
    // This logic manages when to signal an interrupt to the host process.

    logic out_interrupt;

    always_ff @(posedge clk) begin
        if      (clear_interrupt) out_interrupt <= 0;
        else if (raise_interrupt) out_interrupt <= 1;
    end

    assign user_interrupt = out_interrupt;

    logic clear_interrupt;
    logic raise_interrupt;

    assign clear_interrupt = reset_this_cycle || write_status || special_opcode_end_this_cycle;

    assign raise_interrupt =
        (parse_standard_opcode_this_cycle && current_byte == DW_LNS_COPY) ||
        (parse_extended_opcode_this_cycle && current_byte == DW_LNE_ENDSEQUENCE) ||
        parse_special_opcode_or_constaddpc_this_cycle;

    // SHARED ADDERS

    logic [27:0] main_adder_dest;
    logic [27:0] main_adder_src0;
    logic [27:0] main_adder_src1;

    assign main_adder_dest = main_adder_src0 + main_adder_src1;

    assign main_adder_src0 =
        add_operand_to_am_address ? am_address :
        add_src1_to_am_line    ? { 12'h0, am_line }   :
                                    28'h0;

    assign main_adder_src1 =
        parse_special_opcode_or_constaddpc_this_cycle ? sign_extended_line_base :
                                                        st_operand;

    logic [27:0] incrementer_dest;
    logic [27:0] incrementer_src0;

    assign incrementer_dest = incrementer_src0 + 28'h1;

    assign incrementer_src0 =
        parse_byte_this_cycle ? { 25'h0, st_ip } :
        increment_am_address  ? am_address :
        28'h0;

    // UNUSED
    // Pmod interface is unused. Drive the outputs to 0 and mark the Pmod inputs as unused to avoid
    // warnings.

    assign uo_out[7:0] = 8'h0;

    wire _unused  = &{ ui_in };

endmodule
