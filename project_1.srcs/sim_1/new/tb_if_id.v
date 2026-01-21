`timescale 1ns/1ps

module tb_if_id;

    reg clk, reset;
    reg write_en, flush;

    reg  [31:0] pc_in, pc_plus4_in, instr_in;
    reg         valid_in;

    wire        valid_out;
    wire [31:0] pc_out, pc_plus4_out, instr_out;

    localparam [31:0] NOP = 32'h0000_0013;

    if_id_reg dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .flush(flush),
        .pc_in(pc_in),
        .pc_plus4_in(pc_plus4_in),
        .instr_in(instr_in),
        .valid_in(valid_in),
        .valid_out(valid_out),
        .pc_out(pc_out),
        .pc_plus4_out(pc_plus4_out),
        .instr_out(instr_out)
    );

    initial clk = 1'b0;
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

    task expect1;
        input got;
        input exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%b exp=%b (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %b (t=%0t)", msg, got, $time);
            end
        end
    endtask

    initial begin
        reset = 1;
        write_en = 0;
        flush = 0;

        pc_in = 0;
        pc_plus4_in = 0;
        instr_in = 0;
        valid_in = 0;

        @(posedge clk);
        @(posedge clk);
        expect32(pc_out,       32'h0000_0000, "reset: pc_out");
        expect32(pc_plus4_out, 32'h0000_0000, "reset: pc_plus4_out");
        expect32(instr_out,    NOP,           "reset: instr_out = NOP");
        expect1 (valid_out,    1'b0,          "reset: valid_out = 0");

        reset = 0;

        @(negedge clk);
        write_en = 1;
        flush = 0;
        pc_in = 32'h0000_0010;
        pc_plus4_in = 32'h0000_0014;
        instr_in = 32'hDEAD_BEEF;
        valid_in = 1'b1;

        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0010, "write: pc_out");
        expect32(pc_plus4_out, 32'h0000_0014, "write: pc_plus4_out");
        expect32(instr_out,    32'hDEAD_BEEF, "write: instr_out");
        expect1 (valid_out,    1'b1,          "write: valid_out");

        @(negedge clk);
        write_en = 0;
        pc_in = 32'h0000_0020;
        pc_plus4_in = 32'h0000_0024;
        instr_in = 32'hCAFE_BABE;
        valid_in = 1'b0;

        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0010, "stall: pc_out se mantiene");
        expect32(pc_plus4_out, 32'h0000_0014, "stall: pc_plus4_out se mantiene");
        expect32(instr_out,    32'hDEAD_BEEF, "stall: instr_out se mantiene");
        expect1 (valid_out,    1'b1,          "stall: valid_out se mantiene");

        @(negedge clk);
        flush = 1;
        write_en = 1;
        pc_in = 32'h0000_0030;
        pc_plus4_in = 32'h0000_0034;
        instr_in = 32'h1234_5678;
        valid_in = 1'b1;

        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0000, "flush: pc_out=0");
        expect32(pc_plus4_out, 32'h0000_0000, "flush: pc_plus4_out=0");
        expect32(instr_out,    NOP,           "flush: instr_out=NOP");
        expect1 (valid_out,    1'b0,          "flush: valid_out=0");

        @(negedge clk);
        flush = 0;
        write_en = 1;
        pc_in = 32'h0000_0040;
        pc_plus4_in = 32'h0000_0044;
        instr_in = 32'h0BAD_F00D;
        valid_in = 1'b0;

        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0040, "write2: pc_out");
        expect32(pc_plus4_out, 32'h0000_0044, "write2: pc_plus4_out");
        expect32(instr_out,    32'h0BAD_F00D, "write2: instr_out");
        expect1 (valid_out,    1'b0,          "write2: valid_out");

        $display("========================================");
        $display("FIN: tb_if_id OK");
        $display("========================================");
        $finish;
    end

endmodule
