`timescale 1ns / 1ps

module if_stage #(
    parameter XLEN       = 32,
    parameter IM_DEPTH   = 256,
    parameter IMEM_FILE  = ""
)(
    input  wire             clk,
    input  wire             reset,

    // Control
    input  wire             pc_en,          // 1 = avanza PC, 0 = mantiene (stall)
    input  wire             pcsrc,          // 0 -> PC+4, 1 -> branch_target
    input  wire [XLEN-1:0]  branch_target,

    // --- IMEM reprogramación ---
    input  wire             imem_dbg_we,
    input  wire [XLEN-1:0]  imem_dbg_addr,
    input  wire [31:0]      imem_dbg_wdata,

    // --- Soft reset de fetch (cargar PC) ---
    input  wire             dbg_load_pc,
    input  wire [XLEN-1:0]  dbg_pc_value,

    output wire [XLEN-1:0]  pc,
    output wire [XLEN-1:0]  pc_plus4,
    output wire [31:0]      instr
);

    wire [XLEN-1:0] next_pc;

    assign pc_plus4 = pc + 32'd4;

    assign next_pc  = (pcsrc) ? branch_target : pc_plus4;

    pc_reg #(.XLEN(XLEN)) u_pc (
        .clk(clk),
        .reset(reset),
        .en(pc_en),
        .next_pc(next_pc),

        .dbg_load_pc(dbg_load_pc),
        .dbg_pc_value(dbg_pc_value),

        .pc(pc)
    );

    imem_simple #(
        .XLEN(XLEN),
        .DEPTH(IM_DEPTH),
        .MEM_FILE(IMEM_FILE)
    ) u_imem (
        .addr(pc),
        .instr(instr),

        .clk(clk),
        .dbg_we(imem_dbg_we),
        .dbg_addr(imem_dbg_addr),
        .dbg_wdata(imem_dbg_wdata)
    );

endmodule
