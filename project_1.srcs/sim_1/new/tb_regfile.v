`timescale 1ns / 1ps

`timescale 1ns/1ps

module tb_regfile;

    localparam XLEN = 32;

    reg clk;
    reg reset;

    reg we;
    reg [4:0] rs1, rs2, rd;
    reg [XLEN-1:0] wd;
    wire [XLEN-1:0] rd1, rd2;

    // DUT
    regfile #(.XLEN(XLEN)) dut (
        .clk(clk),
        .reset(reset),
        .we(we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .wd(wd),
        .rd1(rd1),
        .rd2(rd2)
    );

    // Clock 100 MHz => periodo 10ns
    initial clk = 0;
    always #5 clk = ~clk;

    // Helpers: escribir en un registro en un flanco
    task write_reg(input [4:0] waddr, input [XLEN-1:0] wdata);
    begin
        @(negedge clk);
        we = 1;
        rd = waddr;
        wd = wdata;
        @(negedge clk);
        we = 0;
    end
    endtask

    initial begin
        // Inicialización
        reset = 1;
        we = 0;
        rs1 = 0; rs2 = 0;
        rd = 0;  wd = 0;

        // Soltar reset
        #20;
        reset = 0;

        // 1) Escribo x1 = 5
        write_reg(5'd1, 32'd5);

        // 2) Escribo x2 = 10
        write_reg(5'd2, 32'd10);

        // 3) Leo rs1=x1, rs2=x2
        rs1 = 5'd1;
        rs2 = 5'd2;
        #1; // pequeña espera para lectura combinacional

        if (rd1 !== 32'd5)  $display("ERROR: x1 esperado 5, leido %0d", rd1);
        else               $display("OK: x1 = %0d", rd1);

        if (rd2 !== 32'd10) $display("ERROR: x2 esperado 10, leido %0d", rd2);
        else                $display("OK: x2 = %0d", rd2);

        // 4) Intento escribir x0 = 123 (debe ignorarse)
        write_reg(5'd0, 32'd123);

        // 5) Leo x0 por ambos puertos (debe dar 0)
        rs1 = 5'd0;
        rs2 = 5'd0;
        #1;

        if (rd1 !== 32'd0)  $display("ERROR: x0 esperado 0, leido %0d", rd1);
        else               $display("OK: x0 = %0d (hardwired)", rd1);

        if (rd2 !== 32'd0)  $display("ERROR: x0 esperado 0, leido %0d", rd2);
        else               $display("OK: x0 = %0d (hardwired)", rd2);

        $display("Fin TB regfile.");
        $stop;
    end

endmodule
