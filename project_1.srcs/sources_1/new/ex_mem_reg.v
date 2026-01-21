`timescale 1ns / 1ps

// ex_mem_reg.v
// Registro de pipeline EX/MEM
// Guarda resultados de EX para la etapa MEM

module ex_mem_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        write_en,
    input  wire        flush,
    
    input  wire [31:0] pc_plus4_in,

    // -------- DATA desde EX --------
    input  wire [31:0] alu_result_in,
    input  wire [31:0] rs2_pass_in,
    input  wire [31:0] branch_target_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,

    // -------- CONTROL desde EX (M / WB) --------
    input  wire        mem_read_in,
    input  wire        mem_write_in,

    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    
    input  wire        wb_sel_pc4_in,

    // (opcional) branch
    input  wire        branch_taken_in,
    
    input  wire valid_in,

    // -------- DATA hacia MEM --------
    output reg  [31:0] alu_result_out,
    output reg  [31:0] rs2_pass_out,
    output reg  [31:0] branch_target_out,
    output reg  [4:0]  rd_out,
    output reg  [2:0]  funct3_out,

    // -------- CONTROL hacia MEM / WB --------
    output reg         mem_read_out,
    output reg         mem_write_out,

    output reg         reg_write_out,
    output reg         mem_to_reg_out,

    output reg         branch_taken_out,
    
    output reg  [31:0] pc_plus4_out,
    output reg         wb_sel_pc4_out,
    output reg  valid_out
);

    // Inserta burbuja
    task automatic bubble;
    begin
        alu_result_out    <= 32'b0;
        rs2_pass_out      <= 32'b0;
        branch_target_out <= 32'b0;
        rd_out            <= 5'b0;
        funct3_out        <= 3'b0;
        pc_plus4_out      <= 32'b0;

        mem_read_out      <= 1'b0;
        mem_write_out     <= 1'b0;
        reg_write_out     <= 1'b0;
        mem_to_reg_out    <= 1'b0;
        branch_taken_out  <= 1'b0;
        wb_sel_pc4_out      <= 1'b0;
        valid_out <= 1'b0;
    end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            bubble();
        end else if (flush) begin
            bubble();
        end else if (write_en) begin
            alu_result_out    <= alu_result_in;
            rs2_pass_out      <= rs2_pass_in;
            branch_target_out <= branch_target_in;
            rd_out            <= rd_in;
            funct3_out        <= funct3_in;
            pc_plus4_out      <= pc_plus4_in;

            mem_read_out      <= mem_read_in;
            mem_write_out     <= mem_write_in;
            reg_write_out     <= reg_write_in;
            mem_to_reg_out    <= mem_to_reg_in;
            branch_taken_out  <= branch_taken_in;
            wb_sel_pc4_out    <= wb_sel_pc4_in;
            valid_out <= valid_in;
        end
        // else: stall → mantener
    end

endmodule
