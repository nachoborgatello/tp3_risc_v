`timescale 1ns/1ps

module tb_regfile;

    localparam XLEN = 32;

    reg clk, reset;
    reg we;
    reg [4:0] rs1, rs2, rd;
    reg [XLEN-1:0] wd;
    wire [XLEN-1:0] rd1, rd2;

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

    initial clk = 0;
    always #5 clk = ~clk;

    task expect32;
        input [31:0] got;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%h exp=%h (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %h (t=%0t)", msg, got, $time);
            end
        end
    endtask

    task write_reg;
        input [4:0] waddr;
        input [XLEN-1:0] wdata;
        begin
            @(negedge clk);
            we = 1'b1;
            rd = waddr;
            wd = wdata;
            @(posedge clk);
            #1;
            we = 1'b0;
        end
    endtask

    initial begin
        reset = 1;
        we = 0;
        rs1 = 0; rs2 = 0; rd = 0; wd = 0;

        @(posedge clk);
        @(posedge clk);
        reset = 0;

        rs1 = 5'd1; rs2 = 5'd2; #1;
        expect32(rd1, 32'd0, "post-reset: x1=0");
        expect32(rd2, 32'd0, "post-reset: x2=0");

        write_reg(5'd1, 32'd5);
        write_reg(5'd2, 32'd10);

        rs1 = 5'd1; rs2 = 5'd2; #1;
        expect32(rd1, 32'd5,  "read: x1=5");
        expect32(rd2, 32'd10, "read: x2=10");

        write_reg(5'd0, 32'd123);
        rs1 = 5'd0; rs2 = 5'd0; #1;
        expect32(rd1, 32'd0, "x0 hardwired (rd1)");
        expect32(rd2, 32'd0, "x0 hardwired (rd2)");

        @(negedge clk);
        rs1 = 5'd3;
        rs2 = 5'd4;
        rd  = 5'd3;
        wd  = 32'hA5A5_0003;
        we  = 1'b1;
        #1;
        expect32(rd1, 32'hA5A5_0003, "write-first: rd1 ve wd cuando rs1==rd");
        expect32(rd2, 32'd0,         "write-first: rd2 sin match queda en 0");
        @(posedge clk);
        #1;
        we = 1'b0;

        @(negedge clk);
        rs1 = 5'd5;
        rs2 = 5'd6;
        rd  = 5'd6;
        wd  = 32'h5A5A_0006;
        we  = 1'b1;
        #1;
        expect32(rd2, 32'h5A5A_0006, "write-first: rd2 ve wd cuando rs2==rd");
        @(posedge clk);
        #1;
        we = 1'b0;

        rs1 = 5'd3; rs2 = 5'd6; #1;
        expect32(rd1, 32'hA5A5_0003, "persist: x3 escrito");
        expect32(rd2, 32'h5A5A_0006, "persist: x6 escrito");

        $display("========================================");
        $display("FIN: tb_regfile OK");
        $display("========================================");
        $finish;
    end

endmodule
