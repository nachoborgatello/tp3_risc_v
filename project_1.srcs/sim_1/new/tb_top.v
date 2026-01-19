`timescale 1ns/1ps

module tb_top;

    reg clk, reset;

    wire [31:0] dbg_pc, dbg_x1, dbg_x2, dbg_x3, dbg_x4, dbg_x5, dbg_x6, dbg_x7, dbg_x8, dbg_x9, dbg_x10, dbg_x11, dbg_x12, dbg_mem_word0;

    cpu_top #(
        .IMEM_FILE("prog.mem"),
        .DMEM_FILE("")
    ) dut (
        .clk(clk),
        .reset(reset),
        .dbg_pc(dbg_pc),
        .dbg_x1(dbg_x1),
        .dbg_x2(dbg_x2),
        .dbg_x3(dbg_x3),
        .dbg_x4(dbg_x4),
        .dbg_x5(dbg_x5),
        .dbg_x6(dbg_x6),
        .dbg_x7(dbg_x7),
        .dbg_x8(dbg_x8),
        .dbg_x9(dbg_x9),
        .dbg_x10(dbg_x10),
        .dbg_x11(dbg_x11),
        .dbg_x12(dbg_x12),
        .dbg_mem_word0(dbg_mem_word0)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check32(input [31:0] got, input [31:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
        else            $display("OK    %0s", name);
    end
    endtask

    initial begin
        reset = 1;
        #30;
        reset = 0;

        // correr 300 ciclos (suficiente para el programa con NOPs)
        #(10*300);
        
        check32(dbg_x1 ,  32'h00000002, "x1");
        check32(dbg_x2 ,  32'h0000000B, "x2");
        check32(dbg_x3 ,  32'h000000B8, "x3");
        check32(dbg_x4 ,  32'h00000040, "x4");
        check32(dbg_x5 ,  32'h000000A8, "x5");
        check32(dbg_x6 ,  32'h00000002, "x6");
        check32(dbg_x7 ,  32'h00000001, "x7");
        check32(dbg_x8 ,  32'h0000000B, "x8");
        check32(dbg_x9 ,  32'h000000BC, "x9");
        check32(dbg_x10,  32'h00000007, "x10");
        check32(dbg_x11,  32'h00000001, "x11");
        check32(dbg_x12,  32'h00000002, "x12");
        check32(dbg_mem_word0, 32'h007F0000, "mem[0..3] word0");

        $display("Fin TB TOP CHECK.");
        $stop;
    end

endmodule
