`timescale 1ns/1ps

module tb_control_unit;

    reg  [6:0] opcode;

    wire reg_write, mem_read, mem_write, mem_to_reg, alu_src;
    wire branch, jump, jalr, wb_sel_pc4;
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
        .wb_sel_pc4(wb_sel_pc4),
        .alu_op(alu_op)
    );

    task expect;
        input got;
        input exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%b exp=%b", msg, got, exp);
                $fatal;
            end
        end
    endtask

    task expect2;
        input [1:0] got;
        input [1:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%b exp=%b", msg, got, exp);
                $fatal;
            end
        end
    endtask

    task check_defaults_zero;
        begin
            expect(reg_write,  0, "default reg_write");
            expect(mem_read,   0, "default mem_read");
            expect(mem_write,  0, "default mem_write");
            expect(mem_to_reg, 0, "default mem_to_reg");
            expect(alu_src,    0, "default alu_src");
            expect(branch,     0, "default branch");
            expect(jump,       0, "default jump");
            expect(jalr,       0, "default jalr");
            expect(wb_sel_pc4, 0, "default wb_sel_pc4");
            expect2(alu_op, 2'b00, "default alu_op");
        end
    endtask

    initial begin
        opcode = 7'h00; #1;
        check_defaults_zero();

        opcode = 7'b0110011; #1; // OP
        expect(reg_write, 1, "OP reg_write");
        expect(alu_src,   0, "OP alu_src");
        expect2(alu_op, 2'b10, "OP alu_op");

        opcode = 7'b0010011; #1; // OP_IMM
        expect(reg_write, 1, "OP_IMM reg_write");
        expect(alu_src,   1, "OP_IMM alu_src");
        expect2(alu_op, 2'b11, "OP_IMM alu_op");

        opcode = 7'b0000011; #1; // LOAD
        expect(reg_write,  1, "LOAD reg_write");
        expect(mem_read,   1, "LOAD mem_read");
        expect(mem_to_reg, 1, "LOAD mem_to_reg");
        expect(alu_src,    1, "LOAD alu_src");
        expect2(alu_op, 2'b00, "LOAD alu_op");

        opcode = 7'b0100011; #1; // STORE
        expect(mem_write, 1, "STORE mem_write");
        expect(alu_src,   1, "STORE alu_src");
        expect2(alu_op, 2'b00, "STORE alu_op");

        opcode = 7'b1100011; #1; // BRANCH
        expect(branch,  1, "BRANCH branch");
        expect(alu_src, 0, "BRANCH alu_src");
        expect2(alu_op, 2'b01, "BRANCH alu_op");

        opcode = 7'b1101111; #1; // JAL
        expect(reg_write,  1, "JAL reg_write");
        expect(jump,       1, "JAL jump");
        expect(wb_sel_pc4, 1, "JAL wb_sel_pc4");

        opcode = 7'b1100111; #1; // JALR
        expect(reg_write,  1, "JALR reg_write");
        expect(jalr,       1, "JALR jalr");
        expect(wb_sel_pc4, 1, "JALR wb_sel_pc4");
        expect(alu_src,    1, "JALR alu_src");
        expect2(alu_op, 2'b00, "JALR alu_op");

        opcode = 7'b0110111; #1; // LUI
        expect(reg_write, 1, "LUI reg_write");
        expect(alu_src,   1, "LUI alu_src");

        opcode = 7'b0010111; #1; // AUIPC
        expect(reg_write, 1, "AUIPC reg_write");
        expect(alu_src,   1, "AUIPC alu_src");
        expect2(alu_op, 2'b00, "AUIPC alu_op");

        $display("========================================");
        $display("FIN: tb_control_unit OK");
        $display("========================================");
        $finish;
    end

endmodule
