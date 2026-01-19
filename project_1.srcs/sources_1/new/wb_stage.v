`timescale 1ns / 1ps

module wb_stage (
    input  wire [31:0] mem_read_data,
    input  wire [31:0] alu_result,
    input  wire [31:0] pc_plus4_mwb,
    input  wire        mem_to_reg,
    input  wire        reg_write_in,
    input  wire        wb_sel_pc4_mwb,
    input  wire [4:0]  rd_in,

    output wire [31:0] wb_wd,
    output wire        wb_we,
    output wire [4:0]  wb_rd
);

    assign wb_we = reg_write_in;
    assign wb_rd = rd_in;
    assign wb_wd = (wb_sel_pc4_mwb) ? pc_plus4_mwb : (mem_to_reg) ? mem_read_data : alu_result;

endmodule

