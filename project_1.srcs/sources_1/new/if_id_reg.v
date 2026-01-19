`timescale 1ns / 1ps

module if_id_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        write_en,
    input  wire        flush,

    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] instr_in,

    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] instr_out
);

    localparam NOP = 32'h00000013;

    always @(posedge clk) begin
        if (reset) begin
            pc_out    <= 32'b0;
            pc_plus4_out <= 32'b0;
            instr_out <= NOP;
        end else if (flush) begin
            pc_out    <= 32'b0;
            pc_plus4_out  <= 32'b0;
            instr_out <= NOP;
        end else if (write_en) begin
            pc_out    <= pc_in;
            pc_plus4_out  <= pc_plus4_in;
            instr_out <= instr_in;
        end
    end

endmodule
