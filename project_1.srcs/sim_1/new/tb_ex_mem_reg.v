`timescale 1ns/1ps

module tb_ex_mem_reg;

    reg clk, reset;
    reg write_en, flush;

    // Inputs
    reg [31:0] alu_result_in, rs2_pass_in, branch_target_in;
    reg [4:0]  rd_in;
    reg [2:0]  funct3_in; 

    reg mem_read_in, mem_write_in;
    reg reg_write_in, mem_to_reg_in;
    reg branch_taken_in;

    // Outputs
    wire [31:0] alu_result_out, rs2_pass_out, branch_target_out;
    wire [4:0]  rd_out;
    wire [2:0]  funct3_in; 
    
    wire mem_read_out, mem_write_out;
    wire reg_write_out, mem_to_reg_out;
    wire branch_taken_out;

    ex_mem_reg dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .flush(flush),

        .alu_result_in(alu_result_in),
        .rs2_pass_in(rs2_pass_in),
        .branch_target_in(branch_target_in),
        .rd_in(rd_in),
        .funct3_in(funct3_out),

        .mem_read_in(mem_read_in),
        .mem_write_in(mem_write_in),
        .reg_write_in(reg_write_in),
        .mem_to_reg_in(mem_to_reg_in),
        .branch_taken_in(branch_taken_in),

        .alu_result_out(alu_result_out),
        .rs2_pass_out(rs2_pass_out),
        .branch_target_out(branch_target_out),
        .rd_out(rd_out),
        .funct3_out(funct3_out),

        .mem_read_out(mem_read_out),
        .mem_write_out(mem_write_out),
        .reg_write_out(reg_write_out),
        .mem_to_reg_out(mem_to_reg_out),
        .branch_taken_out(branch_taken_out)
    );

    // Clock 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    task check(input cond, input [127:0] msg);
    begin
        if (!cond) $display("ERROR: %0s", msg);
        else       $display("OK   : %0s", msg);
    end
    endtask

    initial begin
        // Init
        reset = 1;
        write_en = 1;
        flush = 0;

        alu_result_in = 32'hAAAA_BBBB;
        rs2_pass_in   = 32'h1111_2222;
        branch_target_in = 32'h0000_0100;
        rd_in = 5'd10;

        mem_read_in   = 0;
        mem_write_in  = 1;
        reg_write_in  = 0;
        mem_to_reg_in = 0;
        branch_taken_in = 1;

        #20;
        reset = 0;

        // 1) Carga normal
        @(posedge clk); #1;
        check(alu_result_out == 32'hAAAA_BBBB, "Load alu_result");
        check(rs2_pass_out   == 32'h1111_2222, "Load rs2_pass");
        check(rd_out         == 5'd10, "Load rd");
        check(mem_write_out  == 1, "Load mem_write");
        check(branch_taken_out == 1, "Load branch_taken");

        // 2) Stall
        write_en = 0;
        alu_result_in = 32'hDEAD_BEEF;
        @(posedge clk); #1;
        check(alu_result_out == 32'hAAAA_BBBB, "Stall keeps alu_result");

        // 3) Reload
        write_en = 1;
        @(posedge clk); #1;
        check(alu_result_out == 32'hDEAD_BEEF, "Reload alu_result");

        // 4) Flush
        flush = 1;
        @(posedge clk); #1;
        flush = 0;

        check(alu_result_out == 32'b0, "Flush alu_result=0");
        check(mem_write_out  == 0, "Flush mem_write=0");
        check(reg_write_out  == 0, "Flush reg_write=0");

        $display("Fin TB EX/MEM.");
        $stop;
    end

endmodule
