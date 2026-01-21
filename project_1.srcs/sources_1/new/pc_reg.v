`timescale 1ns / 1ps

module pc_reg #(
    parameter XLEN = 32
)(
    input  wire             clk,
    input  wire             reset,
    input  wire             en,
    input  wire [XLEN-1:0]  next_pc,

    input  wire             dbg_load_pc,
    input  wire [XLEN-1:0]  dbg_pc_value,

    output reg  [XLEN-1:0]  pc
);

    always @(posedge clk) begin
        if (reset) begin
            pc <= {XLEN{1'b0}};
        end else if (dbg_load_pc) begin
            pc <= dbg_pc_value;
        end else if (en) begin
            pc <= next_pc;
        end
    end

endmodule
