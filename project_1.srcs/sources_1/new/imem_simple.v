`timescale 1ns / 1ps

module imem_simple #(
    parameter XLEN      = 32,
    parameter DEPTH     = 256,
    parameter MEM_FILE  = ""
)(
    // CPU
    input  wire [XLEN-1:0] addr,
    output wire [31:0]     instr,

    // Debug (UART)
    input  wire            clk,
    input  wire            dbg_we,
    input  wire [XLEN-1:0] dbg_addr,   // byte address (tipo PC)
    input  wire [31:0]     dbg_wdata
);

    localparam integer AW = $clog2(DEPTH);

    reg [31:0] mem [0:DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h0000_0013; // NOP

        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    wire [AW-1:0] cpu_word = addr[AW+1:2];
    wire [AW-1:0] dbg_word = dbg_addr[AW+1:2];

    // Lectura combinacional (CPU)
    assign instr = mem[cpu_word];

    // Escritura síncrona (Debug)
    always @(posedge clk) begin
        if (dbg_we) begin
            mem[dbg_word] <= dbg_wdata;
        end
    end

endmodule
