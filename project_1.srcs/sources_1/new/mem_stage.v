`timescale 1ns / 1ps

module mem_stage #(
    parameter DM_BYTES = 4096,
    parameter DM_FILE  = ""
)(
    input  wire        clk,

    // Control
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,

    // Data desde EX/MEM
    input  wire [31:0] alu_result_in, // dirección o resultado ALU
    input  wire [31:0] write_data,    // dato a escribir (stores)

    // Outputs hacia MEM/WB
    output wire [31:0] mem_read_data, // dato leído (ya extendido)
    output wire [31:0] alu_result_out, // passthrough
    
    input  wire [11:0] dbg_byte_addr,
    output wire [7:0]  dbg_byte_data
);

    // Memoria de datos completa RV32
    dmem_rv32 #(
        .BYTES(DM_BYTES),
        .MEM_FILE(DM_FILE)
    ) u_dmem (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .funct3     (funct3),
        .addr       (alu_result_in),
        .write_data (write_data),
        .read_data  (mem_read_data),
        .dbg_byte_addr(dbg_byte_addr),
        .dbg_byte_data(dbg_byte_data)
    );

    // Passthrough del resultado de la ALU
    assign alu_result_out = alu_result_in;

endmodule
