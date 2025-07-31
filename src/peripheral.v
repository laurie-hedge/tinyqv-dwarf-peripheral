/*
 * Copyright (c) 2025 Laurie Hedge
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tqvp_laurie_dwarf5_line_table_accelerator (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);
    localparam RW_8_BIT  = 2'h0;
    localparam RW_16_BIT = 2'h1;
    localparam RW_32_BIT = 2'h2;
    localparam RW_NONE   = 2'h3;

    localparam PROGRAM_HEADER    = 6'h0;
    localparam PROGRAM_CODE      = 6'h1;
    localparam SM_ADDRESS        = 6'h2;
    localparam SM_FILE_DESCRIM   = 6'h3;
    localparam SM_LINE_COL_FLAGS = 6'h4;
    localparam STATUS            = 6'h5;

    localparam STATUS_READY    = 1'b0;
    localparam STATUS_EMIT_ROW = 1'b1;

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

    localparam STATE_READY                  = 4'h0;
    localparam STATE_PAUSE_FOR_EMIT         = 4'h1;
    localparam STATE_PARSE_LEB_128_BYTE0    = 4'h2;
    localparam STATE_PARSE_LEB_128_BYTE1    = 4'h3;
    localparam STATE_PARSE_LEB_128_BYTE2    = 4'h4;
    localparam STATE_PARSE_LEB_128_BYTE3    = 4'h5;
    localparam STATE_PARSE_LEB_128_OVERFLOW = 4'h6;
    localparam STATE_PARSE_U16_BYTE0        = 4'h7;
    localparam STATE_PARSE_U16_BYTE1        = 4'h8;
    localparam STATE_EXEC                   = 4'h9;

    localparam INSTR_NOP         = 3'h0;
    localparam INSTR_ADVANCEPC   = 3'h1;
    localparam INSTR_ADVANCELINE = 3'h2;
    localparam INSTR_SETFILE     = 3'h3;
    localparam INSTR_SETCOLUMN   = 3'h4;

    reg[3:0]  st_state;
    reg[2:0]  st_current_instruction;
    reg       st_leb_signed;

    reg       ph_default_is_stmt;
    reg [7:0] ph_line_base;
    reg [7:0] ph_line_range;
    reg [7:0] ph_opcode_base;

    reg [2:0]  pc_ip;
    reg [1:0]  pc_valid;
    reg [31:0] pc_buffer;
    reg [27:0] pc_operand;
    wire [7:0] pc_next_byte;
    wire       pc_next_valid;
    wire       pc_leb_last_byte;
    wire       pc_sign_extend_one;

    reg [27:1] sm_address;
    reg [15:0] sm_file;
    reg [15:0] sm_line;
    reg [9:0]  sm_column;
    reg        sm_is_stmt;
    reg        sm_basic_block;
    reg        sm_end_sequence;
    reg        sm_prologue_end;
    reg        sm_epilogue_begin;
    reg [15:0] sm_descriminator;

    wire [31:0] out_program_header;
    wire [31:0] out_sm_address;
    wire [31:0] out_sm_file_descrim;
    wire [31:0] out_sm_line_col_flags;
    reg         out_interrupt;
    reg         out_status;

    always @(posedge clk) begin
        if (!rst_n) begin
            st_state           <= STATE_READY;
            out_status         <= STATUS_READY;
            ph_default_is_stmt <= 0;
            ph_line_base       <= 8'h0;
            ph_line_range      <= 8'h0;
            ph_opcode_base     <= 8'h0;
            pc_ip              <= 3'h0;
            pc_valid           <= RW_NONE;
            sm_address         <= 27'h0;
            sm_file            <= 16'h1;
            sm_line            <= 16'h1;
            sm_column          <= 10'h0;
            sm_is_stmt         <= 0;
            sm_basic_block     <= 0;
            sm_end_sequence    <= 0;
            sm_prologue_end    <= 0;
            sm_epilogue_begin  <= 0;
            sm_descriminator   <= 16'h0;
            out_interrupt      <= 0;
        end else if (data_write_n != RW_NONE) begin
            if (address == PROGRAM_HEADER) begin
                st_state           <= STATE_READY;
                out_status         <= STATUS_READY;
                ph_default_is_stmt <= data_in[0];
                pc_ip              <= 3'h0;
                pc_valid           <= data_write_n;
                sm_address         <= 27'h0;
                sm_file            <= 16'h1;
                sm_line            <= 16'h1;
                sm_column          <= 10'h0;
                sm_is_stmt         <= data_in[0];
                sm_basic_block     <= 0;
                sm_end_sequence    <= 0;
                sm_prologue_end    <= 0;
                sm_epilogue_begin  <= 0;
                sm_descriminator   <= 16'h0;
                if (data_write_n[1] != data_write_n[0]) begin
                    ph_line_base <= data_in[15:8];
                end
                if (data_write_n == RW_32_BIT) begin
                    ph_line_range  <= data_in[23:16];
                    ph_opcode_base <= data_in[31:24];
                end
            end else if (address == PROGRAM_CODE) begin
                pc_ip          <= 3'h0;
                pc_valid       <= data_write_n;
                pc_buffer[7:0] <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) begin
                    pc_buffer[15:8] <= data_in[15:8];
                end
                if (data_write_n == RW_32_BIT) begin
                    pc_buffer[31:16] <= data_in[31:16];
                end
            end else if (address == STATUS) begin
                st_state      <= STATE_READY;
                out_status    <= STATUS_READY;
                out_interrupt <= 0;
                if (st_state == STATE_PAUSE_FOR_EMIT) begin
                    sm_basic_block    <= 0;
                    sm_prologue_end   <= 0;
                    sm_epilogue_begin <= 0;
                end
            end
        end else if (st_state == STATE_EXEC) begin
            st_state <= STATE_READY;
            if (st_current_instruction == INSTR_ADVANCEPC) begin
                sm_address <= sm_address + pc_operand[27:1];
            end else if (st_current_instruction == INSTR_ADVANCELINE) begin
                sm_line <= sm_line + pc_operand[15:0];
            end else if (st_current_instruction == INSTR_SETFILE) begin
                sm_file <= pc_operand[15:0];
            end else if (st_current_instruction == INSTR_SETCOLUMN) begin
                sm_column <= pc_operand[9:0];
            end
        end else if (pc_next_valid == 1) begin
            if (st_state == STATE_READY) begin
                if (pc_next_byte == DW_LNS_COPY) begin
                    st_state      <= STATE_PAUSE_FOR_EMIT;
                    out_status    <= STATUS_EMIT_ROW;
                    out_interrupt <= 1;
                end else if (pc_next_byte == DW_LNS_ADVANCEPC) begin
                    st_state               <= STATE_PARSE_LEB_128_BYTE0;
                    st_current_instruction <= INSTR_ADVANCEPC;
                    st_leb_signed          <= 0;
                end else if (pc_next_byte == DW_LNS_ADVANCELINE) begin
                    st_state               <= STATE_PARSE_LEB_128_BYTE0;
                    st_current_instruction <= INSTR_ADVANCELINE;
                    st_leb_signed          <= 1;
                end else if (pc_next_byte == DW_LNS_SETFILE) begin
                    st_state               <= STATE_PARSE_LEB_128_BYTE0;
                    st_current_instruction <= INSTR_SETFILE;
                    st_leb_signed          <= 0;
                end else if (pc_next_byte == DW_LNS_SETCOLUMN) begin
                    st_state               <= STATE_PARSE_LEB_128_BYTE0;
                    st_current_instruction <= INSTR_SETCOLUMN;
                    st_leb_signed          <= 0;
                end else if (pc_next_byte == DW_LNS_NEGATESTMT) begin
                    sm_is_stmt <= ~sm_is_stmt;
                end else if (pc_next_byte == DW_LNS_SETBASICBLOCK) begin
                    sm_basic_block <= 1;
                end else if (pc_next_byte == DW_LNS_FIXEDADVANCEPC) begin
                    st_state               <= STATE_PARSE_U16_BYTE0;
                    st_current_instruction <= INSTR_ADVANCEPC;
                end else if (pc_next_byte == DW_LNS_SETPROLOGUEEND) begin
                    sm_prologue_end <= 1;
                end else if (pc_next_byte == DW_LNS_SETEPILOGUEBEGIN) begin
                    sm_epilogue_begin <= 1;
                end else if (pc_next_byte == DW_LNS_SETISA) begin
                    st_state               <= STATE_PARSE_LEB_128_BYTE0;
                    st_current_instruction <= INSTR_NOP;
                    st_leb_signed          <= 0;
                end
            end else if (st_state == STATE_PARSE_LEB_128_BYTE0) begin
                st_state        <= pc_leb_last_byte ? STATE_EXEC : STATE_PARSE_LEB_128_BYTE1;
                pc_operand[6:0] <= pc_next_byte[6:0];
                if (pc_leb_last_byte) begin
                    pc_operand[27:7] <= pc_sign_extend_one ? 21'h1fffff : 21'h0;
                end
            end else if (st_state == STATE_PARSE_LEB_128_BYTE1) begin
                st_state         <= pc_leb_last_byte ? STATE_EXEC : STATE_PARSE_LEB_128_BYTE2;
                pc_operand[13:7] <= pc_next_byte[6:0];
                if (pc_leb_last_byte) begin
                    pc_operand[27:14] <= pc_sign_extend_one ? 14'h3fff : 14'h0;
                end
            end else if (st_state == STATE_PARSE_LEB_128_BYTE2) begin
                st_state          <= pc_leb_last_byte ? STATE_EXEC : STATE_PARSE_LEB_128_BYTE3;
                pc_operand[20:14] <= pc_next_byte[6:0];
                if (pc_leb_last_byte) begin
                    pc_operand[27:21] <= pc_sign_extend_one ? 7'h7f : 7'h0;
                end
            end else if (st_state == STATE_PARSE_LEB_128_BYTE3) begin
                st_state          <= pc_leb_last_byte ? STATE_EXEC : STATE_PARSE_LEB_128_OVERFLOW;
                pc_operand[27:21] <= pc_next_byte[6:0];
            end else if (st_state == STATE_PARSE_LEB_128_OVERFLOW) begin
                st_state <= pc_leb_last_byte ? STATE_EXEC : STATE_PARSE_LEB_128_OVERFLOW;
            end else if (st_state == STATE_PARSE_U16_BYTE0) begin
                st_state        <= STATE_PARSE_U16_BYTE1;
                pc_operand[7:0] <= pc_next_byte[7:0];
            end else if (st_state == STATE_PARSE_U16_BYTE1) begin
                st_state         <= STATE_EXEC;
                pc_operand[31:8] <= { 16'h0, pc_next_byte[7:0] };
            end
            pc_ip <= st_state != STATE_PAUSE_FOR_EMIT ? pc_ip + 1 : pc_ip;
        end
    end

    assign pc_next_byte       = pc_ip == 3'h0 ? pc_buffer[7:0] :
                                pc_ip == 3'h1 ? pc_buffer[15:8] :
                                pc_ip == 3'h2 ? pc_buffer[23:16] :
                                pc_ip == 3'h3 ? pc_buffer[31:24] :
                                                8'h0;
    assign pc_next_valid      = (pc_valid != RW_NONE && pc_ip == 3'h0) ||
                                (pc_valid == RW_16_BIT && pc_ip[2:1] == 2'h0) ||
                                (pc_valid == RW_32_BIT && pc_ip[2] == 1'h0);
    assign pc_leb_last_byte   = pc_next_byte[7] == 0;
    assign pc_sign_extend_one = pc_next_byte[6] && st_leb_signed;

    assign out_program_header    = { ph_opcode_base, ph_line_range, ph_line_base, 7'h0, ph_default_is_stmt };
    assign out_sm_address        = { 4'h0, sm_address[27:1], 1'b0 };
    assign out_sm_file_descrim   = { sm_descriminator, sm_file };
    assign out_sm_line_col_flags = { 1'h0, sm_epilogue_begin, sm_prologue_end, sm_end_sequence, sm_basic_block, sm_is_stmt, sm_column, sm_line };

    assign user_interrupt = out_interrupt;

    assign data_out[31:16] = data_read_n != RW_32_BIT     ? 16'h0 :
                             address == PROGRAM_HEADER    ? out_program_header[31:16] :
                             address == SM_ADDRESS        ? out_sm_address[31:16] :
                             address == SM_FILE_DESCRIM   ? out_sm_file_descrim[31:16] :
                             address == SM_LINE_COL_FLAGS ? out_sm_line_col_flags[31:16] :
                                                            16'h0;

    assign data_out[15:8] = data_read_n[0] == data_read_n[1] ? 8'h0 :
                            address == PROGRAM_HEADER        ? out_program_header[15:8] :
                            address == SM_ADDRESS            ? out_sm_address[15:8] :
                            address == SM_FILE_DESCRIM       ? out_sm_file_descrim[15:8] :
                            address == SM_LINE_COL_FLAGS     ? out_sm_line_col_flags[15:8] :
                                                               8'h0;

    assign data_out[7:0] = data_read_n == RW_NONE       ? 8'h0 :
                           address == PROGRAM_HEADER    ? out_program_header[7:0] :
                           address == SM_ADDRESS        ? out_sm_address[7:0] :
                           address == SM_FILE_DESCRIM   ? out_sm_file_descrim[7:0] :
                           address == SM_LINE_COL_FLAGS ? out_sm_line_col_flags[7:0] :
                           address == STATUS            ? { 7'h0, out_status } :
                                                          8'h0;

    assign data_ready = 1;

    assign uo_out = 8'h0;
    wire _unused  = &{ ui_in };
endmodule
