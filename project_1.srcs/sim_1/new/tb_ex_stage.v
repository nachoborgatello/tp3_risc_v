`timescale 1ns/1ps

module tb_ex_stage;

    // Inputs
    reg [31:0] pc_in, rs1_data_in, rs2_data_in, imm_in;
    reg        alu_src_in;
    reg [1:0]  alu_op_in;
    reg [2:0]  funct3_in;
    reg [6:0]  funct7_in;
    reg        branch_in;

    // Outputs
    wire [31:0] alu_result_out, rs2_pass_out, branch_target_out;
    wire        branch_taken_out;
    wire        zero_out, lt_out, ltu_out;

    ex_stage dut (
        .pc_in(pc_in),
        .rs1_data_in(rs1_data_in),
        .rs2_data_in(rs2_data_in),
        .imm_in(imm_in),
        .alu_src_in(alu_src_in),
        .alu_op_in(alu_op_in),
        .funct3_in(funct3_in),
        .funct7_in(funct7_in),
        .branch_in(branch_in),
        .alu_result_out(alu_result_out),
        .rs2_pass_out(rs2_pass_out),
        .branch_target_out(branch_target_out),
        .branch_taken_out(branch_taken_out),
        .zero_out(zero_out),
        .lt_out(lt_out),
        .ltu_out(ltu_out)
    );

    // Helpers
    task check32(input [31:0] got, input [31:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
        else            $display("OK    %0s", name);
    end
    endtask

    task check1(input got, input exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%0d exp=%0d", name, got, exp);
        else             $display("OK    %0s", name);
    end
    endtask

    // Espera para que se estabilicen señales combinacionales
    task settle;
    begin
        #5;
    end
    endtask

    localparam [2:0] F3_BEQ = 3'b000;
    localparam [2:0] F3_BNE = 3'b001;

    initial begin
        // Inicialización fuerte: evitar X desde el arranque
        pc_in = 32'h0;
        rs1_data_in = 32'h0;
        rs2_data_in = 32'h0;
        imm_in = 32'h0;
        alu_src_in = 1'b0;
        alu_op_in  = 2'b00;
        funct3_in  = 3'b000;
        funct7_in  = 7'b0000000;
        branch_in  = 1'b0;

        settle();

        // -------------------------
        // Caso 1: ADDI (10 + 5 = 15)
        pc_in       = 32'h0000_0100;
        rs1_data_in = 32'd10;
        rs2_data_in = 32'd0;
        imm_in      = 32'd5;
        alu_src_in  = 1;
        alu_op_in   = 2'b11;     // I-type
        funct3_in   = 3'b000;    // ADDI
        funct7_in   = 7'b0000000;
        branch_in   = 0;

        settle();
        check32(alu_result_out, 32'd15, "ADDI: alu_result");
        check1(branch_taken_out, 1'b0, "ADDI: branch_taken=0");

        // -------------------------
        // Caso 2: ADD (7 + 9 = 16)
        rs1_data_in = 32'd7;
        rs2_data_in = 32'd9;
        imm_in      = 32'd0;
        alu_src_in  = 0;
        alu_op_in   = 2'b10;     // R-type
        funct3_in   = 3'b000;    // ADD/SUB
        funct7_in   = 7'b0000000;

        settle();
        check32(alu_result_out, 32'd16, "ADD: alu_result");

        // -------------------------
        // Caso 3: SUB (7 - 9 = -2)
        funct7_in   = 7'b0100000;

        settle();
        check32(alu_result_out, 32'hFFFF_FFFE, "SUB: 7-9 = -2");

        // -------------------------
        // Caso 4: BEQ tomado (55 == 55), target pc+16
        pc_in       = 32'h0000_0200;
        imm_in      = 32'd16;
        rs1_data_in = 32'd55;
        rs2_data_in = 32'd55;
        alu_src_in  = 0;
        alu_op_in   = 2'b01;     // branch => SUB compare
        funct3_in   = F3_BEQ;
        funct7_in   = 7'b0000000;
        branch_in   = 1;

        settle();
        check1(branch_taken_out, 1'b1, "BEQ taken");
        check32(branch_target_out, 32'h0000_0210, "BEQ target pc+16");

        // -------------------------
        // Caso 5: BEQ no tomado (55 != 54)
        rs2_data_in = 32'd54;

        settle();
        check1(branch_taken_out, 1'b0, "BEQ not taken");

        // -------------------------
        // Caso 6: BNE tomado (55 != 54)
        funct3_in   = F3_BNE;

        settle();
        check1(branch_taken_out, 1'b1, "BNE taken");

        // -------------------------
        // Caso 7: BNE no tomado (55 == 55)
        rs2_data_in = 32'd55;

        settle();
        check1(branch_taken_out, 1'b0, "BNE not taken");

        $display("Fin TB EX stage.");
        $stop;
    end

endmodule
