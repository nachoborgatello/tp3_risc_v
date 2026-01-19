`timescale 1ns / 1ps

module tb_control_unit;

    reg  [6:0] opcode;

    wire reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump, jalr;
    wire [1:0] alu_op;

    control_unit dut (
        .opcode(opcode),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .alu_src(alu_src),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .alu_op(alu_op)
    );

    // opcodes (mismos que en el DUT)
    localparam [6:0] OP      = 7'b0110011;
    localparam [6:0] OP_IMM  = 7'b0010011;
    localparam [6:0] LOAD    = 7'b0000011;
    localparam [6:0] STORE   = 7'b0100011;
    localparam [6:0] BRANCH  = 7'b1100011;
    localparam [6:0] JAL     = 7'b1101111;
    localparam [6:0] JALR    = 7'b1100111;
    localparam [6:0] LUI     = 7'b0110111;
    localparam [6:0] AUIPC   = 7'b0010111;

    task check(
        input [6:0] op,
        input exp_reg_write,
        input exp_mem_read,
        input exp_mem_write,
        input exp_mem_to_reg,
        input exp_alu_src,
        input exp_branch,
        input exp_jump,
        input exp_jalr,
        input [1:0] exp_alu_op,
        input [127:0] name
    );
    begin
        opcode = op;
        #1;
        if (reg_write!==exp_reg_write || mem_read!==exp_mem_read || mem_write!==exp_mem_write ||
            mem_to_reg!==exp_mem_to_reg || alu_src!==exp_alu_src || branch!==exp_branch ||
            jump!==exp_jump || jalr!==exp_jalr || alu_op!==exp_alu_op) begin

            $display("ERROR %0s", name);
            $display(" got: RW=%0d MR=%0d MW=%0d M2R=%0d AS=%0d BR=%0d JP=%0d JR=%0d ALUOp=%b",
                      reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump, jalr, alu_op);
            $display(" exp: RW=%0d MR=%0d MW=%0d M2R=%0d AS=%0d BR=%0d JP=%0d JR=%0d ALUOp=%b",
                      exp_reg_write, exp_mem_read, exp_mem_write, exp_mem_to_reg, exp_alu_src,
                      exp_branch, exp_jump, exp_jalr, exp_alu_op);
        end else begin
            $display("OK    %0s", name);
        end
    end
    endtask

    initial begin
        // R-type
        check(OP,     1,0,0,0,0,0,0,0, 2'b10, "R-type OP");

        // I-type ALU
        check(OP_IMM, 1,0,0,0,1,0,0,0, 2'b11, "I-type OP-IMM");

        // LOAD
        check(LOAD,   1,1,0,1,1,0,0,0, 2'b00, "LOAD");

        // STORE
        check(STORE,  0,0,1,0,1,0,0,0, 2'b00, "STORE");

        // BRANCH
        check(BRANCH, 0,0,0,0,0,1,0,0, 2'b01, "BRANCH");

        // JAL
        check(JAL,    1,0,0,0,0,0,1,0, 2'b00, "JAL");

        // JALR
        check(JALR,   1,0,0,0,1,0,0,1, 2'b00, "JALR");

        // LUI
        check(LUI,    1,0,0,0,1,0,0,0, 2'b00, "LUI");

        // AUIPC
        check(AUIPC,  1,0,0,0,1,0,0,0, 2'b00, "AUIPC");

        $display("Fin TB control_unit.");
        $stop;
    end

endmodule

