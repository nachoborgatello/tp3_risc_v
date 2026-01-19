`timescale 1ns / 1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        write_en,
    input  wire        flush,

    // -------- DATA desde MEM --------
    input  wire [31:0] mem_read_data_in,
    input  wire [31:0] alu_result_in,
    input  wire [4:0]  rd_in,

    // -------- CONTROL WB desde EX/MEM (o MEM) --------
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    
    input  wire [31:0] pc_plus4_in,
    input  wire        wb_sel_pc4_in,

    // -------- DATA hacia WB --------
    output reg  [31:0] mem_read_data_out,
    output reg  [31:0] alu_result_out,
    output reg  [4:0]  rd_out,

    // -------- CONTROL hacia WB --------
    output reg         reg_write_out,
    output reg         mem_to_reg_out,
    
    output reg  [31:0] pc_plus4_out,
    output reg         wb_sel_pc4_out
);

    task automatic bubble;
    begin
        mem_read_data_out <= 32'b0;
        alu_result_out    <= 32'b0;
        pc_plus4_out      <= 32'b0;
        rd_out            <= 5'b0;

        reg_write_out     <= 1'b0;
        mem_to_reg_out    <= 1'b0;
        wb_sel_pc4_out      <= 1'b0;
    end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            bubble();
        end else if (flush) begin
            bubble();
        end else if (write_en) begin
            mem_read_data_out <= mem_read_data_in;
            alu_result_out    <= alu_result_in;
            pc_plus4_out      <= pc_plus4_in;
            rd_out            <= rd_in;

            reg_write_out     <= reg_write_in;
            mem_to_reg_out    <= mem_to_reg_in;
            wb_sel_pc4_out    <= wb_sel_pc4_in;
        end
        // else: stall -> mantener
    end

endmodule

