`timescale 1ns/1ps

module tb_alu_control;

    reg  [1:0] alu_op;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    wire [3:0] alu_ctrl;

    alu_control dut (
        .alu_op(alu_op),
        .funct3(funct3),
        .funct7(funct7),
        .alu_ctrl(alu_ctrl)
    );

    task check(input [3:0] exp, input [127:0] name);
    begin
        #1;
        if (alu_ctrl !== exp)
            $display("ERROR %0s: alu_ctrl=%b esperado=%b", name, alu_ctrl, exp);
        else
            $display("OK    %0s", name);
    end
    endtask

    localparam ADD  = 4'b0000;
    localparam SUB  = 4'b0001;
    localparam AND  = 4'b0010;
    localparam OR   = 4'b0011;
    localparam XOR  = 4'b0100;
    localparam SLT  = 4'b0101;
    localparam SLTU = 4'b0110;
    localparam SLL  = 4'b0111;
    localparam SRL  = 4'b1000;
    localparam SRA  = 4'b1001;

    initial begin
        // R-type ADD
        alu_op = 2'b10; funct3 = 3'b000; funct7 = 7'b0000000;
        check(ADD, "R-type ADD");

        // R-type SUB
        funct7 = 7'b0100000;
        check(SUB, "R-type SUB");

        // I-type ANDI
        alu_op = 2'b11; funct3 = 3'b111; funct7 = 7'b0000000;
        check(AND, "I-type ANDI");

        // I-type SRAI
        funct3 = 3'b101; funct7 = 7'b0100000;
        check(SRA, "I-type SRAI");

        // Branch
        alu_op = 2'b01;
        check(SUB, "Branch SUB");

        $display("Fin TB alu_control.");
        $stop;
    end

endmodule
