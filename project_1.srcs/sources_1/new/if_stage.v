`timescale 1ns / 1ps

module if_stage #(
    parameter XLEN      = 32,
    parameter IM_DEPTH  = 256,
    parameter IMEM_FILE   = ""
)(
    input  wire             clk,
    input  wire             reset,

    // Control
    input  wire             pc_en,         // 1 = avanza PC, 0 = mantiene (stall)
    input  wire             pcsrc,         // 0 -> PC+4, 1 -> branch_target

    // Entrada desde EX/MEM (más adelante)
    input  wire [XLEN-1:0]  branch_target,

    // Salidas
    output wire [XLEN-1:0]  pc,
    output wire [XLEN-1:0]  pc_plus4 ,
    output wire [31:0]      instr
);

    wire [XLEN-1:0] next_pc;

    // Add
    assign pc_plus4 = pc + 32'd4;
    
    // Mux
    assign next_pc  = (pcsrc) ? branch_target : pc_plus4;

    pc_reg #(.XLEN(XLEN)) u_pc (
        .clk(clk),
        .reset(reset),
        .en(pc_en),
        .next_pc(next_pc),
        .pc(pc)
    );

    imem_simple #(
        .XLEN(XLEN),
        .DEPTH(IM_DEPTH),
        .MEM_FILE(IMEM_FILE)
    ) u_imem (
        .addr(pc),
        .instr(instr)
    );

endmodule
