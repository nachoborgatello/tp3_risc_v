`timescale 1ns/1ps

module tb_mem_wb_reg;

    reg clk, reset;
    reg write_en, flush;

    // Inputs
    reg [31:0] mem_read_data_in, alu_result_in;
    reg [4:0]  rd_in;
    reg        reg_write_in, mem_to_reg_in;

    // Outputs
    wire [31:0] mem_read_data_out, alu_result_out;
    wire [4:0]  rd_out;
    wire        reg_write_out, mem_to_reg_out;

    mem_wb_reg dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .flush(flush),

        .mem_read_data_in(mem_read_data_in),
        .alu_result_in(alu_result_in),
        .rd_in(rd_in),

        .reg_write_in(reg_write_in),
        .mem_to_reg_in(mem_to_reg_in),

        .mem_read_data_out(mem_read_data_out),
        .alu_result_out(alu_result_out),
        .rd_out(rd_out),

        .reg_write_out(reg_write_out),
        .mem_to_reg_out(mem_to_reg_out)
    );

    // Clock 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    task check(input cond, input [127:0] msg);
    begin
        if (!cond) $display("ERROR: %0s", msg);
        else       $display("OK   : %0s", msg);
    end
    endtask

    initial begin
        // init
        reset = 1;
        write_en = 1;
        flush = 0;

        mem_read_data_in = 32'hAAAA_0001;
        alu_result_in    = 32'hBBBB_0002;
        rd_in            = 5'd7;

        reg_write_in     = 1;
        mem_to_reg_in    = 1;

        #20;
        reset = 0;

        // 1) Load normal
        @(posedge clk); #1;
        check(mem_read_data_out == 32'hAAAA_0001, "Load mem_read_data");
        check(alu_result_out    == 32'hBBBB_0002, "Load alu_result");
        check(rd_out            == 5'd7, "Load rd");
        check(reg_write_out     == 1'b1, "Load reg_write");
        check(mem_to_reg_out    == 1'b1, "Load mem_to_reg");

        // 2) Stall: cambiar inputs pero outputs no deben cambiar
        write_en = 0;
        mem_read_data_in = 32'h1111_1111;
        alu_result_in    = 32'h2222_2222;
        rd_in            = 5'd10;
        reg_write_in     = 0;
        mem_to_reg_in    = 0;

        @(posedge clk); #1;
        check(mem_read_data_out == 32'hAAAA_0001, "Stall keeps mem_read_data");
        check(alu_result_out    == 32'hBBBB_0002, "Stall keeps alu_result");
        check(rd_out            == 5'd7, "Stall keeps rd");
        check(reg_write_out     == 1'b1, "Stall keeps reg_write");

        // 3) Reload
        write_en = 1;
        @(posedge clk); #1;
        check(mem_read_data_out == 32'h1111_1111, "Reload mem_read_data");
        check(alu_result_out    == 32'h2222_2222, "Reload alu_result");
        check(rd_out            == 5'd10, "Reload rd");
        check(reg_write_out     == 1'b0, "Reload reg_write");
        check(mem_to_reg_out    == 1'b0, "Reload mem_to_reg");

        // 4) Flush: burbuja (controles a 0)
        flush = 1;
        @(posedge clk); #1;
        flush = 0;

        check(reg_write_out  == 1'b0, "Flush reg_write=0");
        check(mem_to_reg_out == 1'b0, "Flush mem_to_reg=0");
        check(rd_out         == 5'd0, "Flush rd=0");

        $display("Fin TB MEM/WB.");
        $stop;
    end

endmodule
