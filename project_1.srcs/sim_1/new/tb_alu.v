`timescale 1ns/1ps

module tb_alu;

    reg  [31:0] a, b;
    reg  [3:0]  alu_ctrl;
    wire [31:0] result;
    wire zero, lt, ltu;

    alu dut (
        .a(a),
        .b(b),
        .alu_ctrl(alu_ctrl),
        .result(result),
        .zero(zero),
        .lt(lt),
        .ltu(ltu)
    );

    task check(input [31:0] exp, input [127:0] name);
    begin
        #1;
        if (result !== exp)
            $display("ERROR %0s: result=%0d esperado=%0d", name, result, exp);
        else
            $display("OK    %0s", name);
    end
    endtask

    initial begin
        // ADD
        a = 10; b = 5; alu_ctrl = 4'b0000;
        check(15, "ADD");

        // SUB
        alu_ctrl = 4'b0001;
        check(5, "SUB");

        // AND
        alu_ctrl = 4'b0010;
        check(0, "AND");

        // SLT (signed)
        a = -1; b = 1; alu_ctrl = 4'b0101;
        check(1, "SLT signed");

        // SLTU (unsigned)
        alu_ctrl = 4'b0110;
        check(0, "SLTU unsigned");

        // SLL
        a = 1; b = 4; alu_ctrl = 4'b0111;
        check(16, "SLL");

        // SRL
        a = 32'h80000000; b = 1; alu_ctrl = 4'b1000;
        check(32'h40000000, "SRL");

        // SRA
        alu_ctrl = 4'b1001;
        check(32'hC0000000, "SRA");

        $display("Fin TB ALU.");
        $stop;
    end

endmodule
