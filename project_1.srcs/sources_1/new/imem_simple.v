`timescale 1ns / 1ps

module imem_simple #(
    parameter XLEN      = 32,
    parameter DEPTH     = 256,
    parameter MEM_FILE  = ""
)(
    input  wire [XLEN-1:0] addr,
    output wire [31:0]     instr
);

    reg [31:0] mem [0:DEPTH-1];
    integer i;
    
    initial begin
        // Por defecto, llenamos con NOPs (ADDI x0,x0,0 = 0x00000013)
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'h00000013;
        end

        if (MEM_FILE != "") begin
            $readmemh(MEM_FILE, mem);
        end
    end

    // Lectura combinacional
    assign instr = mem[addr[XLEN-1:2]];

endmodule
