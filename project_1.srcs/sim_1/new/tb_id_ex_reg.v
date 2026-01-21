`timescale 1ns/1ps

module tb_id_ex_reg;

    reg clk, reset;
    reg write_en, flush;

    reg [31:0] pc_in, pc_plus4_in, rs1_data_in, rs2_data_in, imm_in;
    reg        valid_in;
    reg [4:0]  rs1_in, rs2_in, rd_in;
    reg [2:0]  funct3_in;
    reg [6:0]  funct7_in;

    reg        reg_write_in, mem_to_reg_in;
    reg        mem_read_in, mem_write_in, branch_in;
    reg        alu_src_in;
    reg [1:0]  alu_op_in;
    reg        jump_in, jalr_in, wb_sel_pc4_in;

    wire [31:0] pc_out, pc_plus4_out, rs1_data_out, rs2_data_out, imm_out;
    wire [4:0]  rs1_out, rs2_out, rd_out;
    wire [2:0]  funct3_out;
    wire [6:0]  funct7_out;

    wire reg_write_out, mem_to_reg_out;
    wire mem_read_out, mem_write_out, branch_out;
    wire alu_src_out;
    wire [1:0] alu_op_out;
    wire jump_out, jalr_out, wb_sel_pc4_out, valid_out;

    id_ex_reg dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .flush(flush),

        .pc_in(pc_in),
        .pc_plus4_in(pc_plus4_in),
        .rs1_data_in(rs1_data_in),
        .rs2_data_in(rs2_data_in),
        .imm_in(imm_in),
        .valid_in(valid_in),

        .rs1_in(rs1_in),
        .rs2_in(rs2_in),
        .rd_in(rd_in),
        .funct3_in(funct3_in),
        .funct7_in(funct7_in),

        .reg_write_in(reg_write_in),
        .mem_to_reg_in(mem_to_reg_in),

        .mem_read_in(mem_read_in),
        .mem_write_in(mem_write_in),
        .branch_in(branch_in),

        .alu_src_in(alu_src_in),
        .alu_op_in(alu_op_in),

        .jump_in(jump_in),
        .jalr_in(jalr_in),
        .wb_sel_pc4_in(wb_sel_pc4_in),

        .pc_out(pc_out),
        .pc_plus4_out(pc_plus4_out),
        .rs1_data_out(rs1_data_out),
        .rs2_data_out(rs2_data_out),
        .imm_out(imm_out),

        .rs1_out(rs1_out),
        .rs2_out(rs2_out),
        .rd_out(rd_out),
        .funct3_out(funct3_out),
        .funct7_out(funct7_out),

        .reg_write_out(reg_write_out),
        .mem_to_reg_out(mem_to_reg_out),

        .mem_read_out(mem_read_out),
        .mem_write_out(mem_write_out),
        .branch_out(branch_out),

        .alu_src_out(alu_src_out),
        .alu_op_out(alu_op_out),

        .jump_out(jump_out),
        .jalr_out(jalr_out),
        .valid_out(valid_out),
        .wb_sel_pc4_out(wb_sel_pc4_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

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

    task expect2;
        input [1:0] got;
        input [1:0] exp;
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

    task expect5;
        input [4:0] got;
        input [4:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%0d exp=%0d (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %0d (t=%0t)", msg, got, $time);
            end
        end
    endtask

    initial begin
        reset = 1;
        write_en = 1;
        flush = 0;

        pc_in = 32'h0000_0010;
        pc_plus4_in = 32'h0000_0014;
        rs1_data_in = 32'd100;
        rs2_data_in = 32'd200;
        imm_in = 32'd12;
        valid_in = 1'b1;

        rs1_in = 5'd1;
        rs2_in = 5'd2;
        rd_in  = 5'd3;
        funct3_in = 3'b010;
        funct7_in = 7'b0000000;

        reg_write_in = 1;
        mem_to_reg_in= 0;

        mem_read_in  = 0;
        mem_write_in = 1;
        branch_in    = 0;

        alu_src_in   = 1;
        alu_op_in    = 2'b00;

        jump_in = 0;
        jalr_in = 0;
        wb_sel_pc4_in = 0;

        @(posedge clk);
        @(posedge clk);

        expect32(pc_out,       32'h0, "reset: pc_out=0");
        expect32(pc_plus4_out, 32'h0, "reset: pc_plus4_out=0");
        expect32(rs1_data_out, 32'h0, "reset: rs1_data_out=0");
        expect32(rs2_data_out, 32'h0, "reset: rs2_data_out=0");
        expect32(imm_out,      32'h0, "reset: imm_out=0");
        expect1 (valid_out,    1'b0,  "reset: valid_out=0");
        expect1 (reg_write_out,1'b0,  "reset: reg_write_out=0");
        expect1 (mem_write_out,1'b0,  "reset: mem_write_out=0");

        reset = 0;

        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0010, "load: pc_out");
        expect32(pc_plus4_out, 32'h0000_0014, "load: pc_plus4_out");
        expect32(rs1_data_out, 32'd100,       "load: rs1_data_out");
        expect32(rs2_data_out, 32'd200,       "load: rs2_data_out");
        expect32(imm_out,      32'd12,        "load: imm_out");
        expect5 (rd_out,       5'd3,          "load: rd_out");
        expect1 (mem_write_out,1'b1,          "load: mem_write_out");
        expect1 (alu_src_out,  1'b1,          "load: alu_src_out");
        expect2 (alu_op_out,   2'b00,         "load: alu_op_out");
        expect1 (valid_out,    1'b1,          "load: valid_out");

        write_en = 0;
        pc_in = 32'h0000_0020;
        rs1_data_in = 32'd111;
        mem_write_in = 0;
        valid_in = 1'b0;

        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0010, "stall: pc_out");
        expect32(rs1_data_out, 32'd100,       "stall: rs1_data_out");
        expect1 (mem_write_out,1'b1,          "stall: mem_write_out");
        expect1 (valid_out,    1'b1,          "stall: valid_out");

        write_en = 1;
        @(posedge clk); #1;
        expect32(pc_out,       32'h0000_0020, "reload: pc_out");
        expect32(rs1_data_out, 32'd111,       "reload: rs1_data_out");
        expect1 (mem_write_out,1'b0,          "reload: mem_write_out");
        expect1 (valid_out,    1'b0,          "reload: valid_out");

        flush = 1;
        @(posedge clk); #1;
        flush = 0;

        expect32(pc_out,       32'h0, "flush: pc_out=0");
        expect32(pc_plus4_out, 32'h0, "flush: pc_plus4_out=0");
        expect1 (reg_write_out,1'b0,  "flush: reg_write_out=0");
        expect1 (mem_write_out,1'b0,  "flush: mem_write_out=0");
        expect2 (alu_op_out,   2'b00, "flush: alu_op_out=00");
        expect1 (valid_out,    1'b0,  "flush: valid_out=0");

        $display("========================================");
        $display("FIN: tb_id_ex_reg OK");
        $display("========================================");
        $finish;
    end

endmodule
