`timescale 1ns / 1ps

`timescale 1ns/1ps

module tb_if_id;

    reg clk;
    reg reset;

    // IF control
    reg pc_en;
    reg pcsrc;
    reg [31:0] branch_target;

    // IF/ID control
    reg ifid_write_en;
    reg ifid_flush;

    wire [31:0] pc;
    wire [31:0] instr;

    wire [31:0] id_pc;
    wire [31:0] id_instr;

    // IF stage
    if_stage #(
        .IM_DEPTH(64),
        .IM_FILE("prog.mem")
    ) if_u (
        .clk(clk),
        .reset(reset),
        .pc_en(pc_en),
        .pcsrc(pcsrc),
        .branch_target(branch_target),
        .pc(pc),
        .instr(instr)
    );

    // IF/ID register
    if_id_reg ifid_u (
        .clk(clk),
        .reset(reset),
        .write_en(ifid_write_en),
        .flush(ifid_flush),
        .pc_in(pc),
        .instr_in(instr),
        .pc_out(id_pc),
        .instr_out(id_instr)
    );

    // Clock 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // Inicialización
        reset = 1;
        pc_en = 1;
        pcsrc = 0;
        branch_target = 0;
        ifid_write_en = 1;
        ifid_flush = 0;

        #20;
        reset = 0;

        // Pipeline normal
        #40;

        // Stall IF/ID
        ifid_write_en = 0;
        #20;
        ifid_write_en = 1;

        // Flush (simula branch tomado)
        ifid_flush = 1;
        #10;
        ifid_flush = 0;

        #40;
        $stop;
    end

endmodule
