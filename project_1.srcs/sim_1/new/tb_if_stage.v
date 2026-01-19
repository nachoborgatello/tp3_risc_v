`timescale 1ns / 1ps

`timescale 1ns/1ps

module tb_if_stage;

    localparam XLEN = 32;

    reg clk;
    reg reset;

    reg pc_en;
    reg pcsrc;
    reg [XLEN-1:0] branch_target;

    wire [XLEN-1:0] pc;
    wire [XLEN-1:0] pc_plus4;
    wire [31:0] instr;

    // DUT
    if_stage #(
        .XLEN(XLEN),
        .IM_DEPTH(64),
        .IM_FILE("")
    ) dut (
        .clk(clk),
        .reset(reset),
        .pc_en(pc_en),
        .pcsrc(pcsrc),
        .branch_target(branch_target),
        .pc(pc),
        .instr(instr)
    );

    // Clock 100MHz => periodo 10ns
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // Inicialización
        reset = 1;
        pc_en = 1;
        pcsrc = 0;
        branch_target = 0;

        // Mantener reset 2 ciclos
        #25;
        reset = 0;

        // Dejar correr 5 ciclos (PC debe ir: 0,4,8,12,16,...)
        #50;

        // Probar stall: PC no debe cambiar durante 3 ciclos
        pc_en = 0;
        #30;
        pc_en = 1;

        // Probar "branch": saltar a 0x40
        branch_target = 32'h0000_0040;
        pcsrc = 1;
        #10;          // un ciclo
        pcsrc = 0;    // volver a PC+4

        // Correr un poco más
        #50;

        $stop;
    end

endmodule
