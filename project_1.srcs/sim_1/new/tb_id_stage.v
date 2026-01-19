`timescale 1ns/1ps

module tb_id_stage;

    reg clk;
    reg reset;

    reg  [31:0] pc_in;
    reg  [31:0] instr_in;

    // WB interface
    reg         wb_reg_write;
    reg  [4:0]  wb_rd;
    reg  [31:0] wb_wd;

    // Outputs
    wire [6:0]  opcode;
    wire [4:0]  rd;
    wire [2:0]  funct3;
    wire [4:0]  rs1, rs2;
    wire [6:0]  funct7;

    wire [31:0] rs1_data, rs2_data, imm;

    wire        reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump, jalr;
    wire [1:0]  alu_op;

    id_stage dut (
        .clk(clk),
        .reset(reset),
        .pc_in(pc_in),
        .instr_in(instr_in),

        .wb_reg_write(wb_reg_write),
        .wb_rd(wb_rd),
        .wb_wd(wb_wd),

        .opcode(opcode),
        .rd(rd),
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .funct7(funct7),

        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .imm(imm),

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

    // Clock 100MHz => 10ns
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper: escribir un registro vía WB en un flanco
    task wb_write(input [4:0] r, input [31:0] v);
    begin
        @(negedge clk);
        wb_reg_write = 1;
        wb_rd = r;
        wb_wd = v;
        @(negedge clk);
        wb_reg_write = 0;
        wb_rd = 0;
        wb_wd = 0;
    end
    endtask

    // Helper: check simple
    task check(input cond, input [127:0] msg);
    begin
        if (!cond) $display("ERROR: %0s", msg);
        else       $display("OK   : %0s", msg);
    end
    endtask

    initial begin
        // init
        reset = 1;
        pc_in = 0;
        instr_in = 32'h00000013;

        wb_reg_write = 0;
        wb_rd = 0;
        wb_wd = 0;

        // release reset
        #20;
        reset = 0;

        // 1) Cargar registros: x1=100, x2=200
        wb_write(5'd1, 32'd100);
        wb_write(5'd2, 32'd200);

        // ------------------------------------------------------------
        // Caso A: ADDI x3, x1, 5
        // opcode=0010011, funct3=000, rs1=x1(1), rd=x3(3), imm=5
        // encoding conocido: 0x00508193
        instr_in = 32'h00508193; // addi x3,x1,5
        #1;

        check(rs1 == 5'd1, "ADDI: rs1=1");
        check(rd  == 5'd3, "ADDI: rd=3");
        check(rs1_data == 32'd100, "ADDI: rs1_data=100");
        check(imm == 32'd5, "ADDI: imm=5");
        check(reg_write==1 && alu_src==1 && alu_op==2'b11, "ADDI: control (reg_write, alu_src, alu_op)");

        // ------------------------------------------------------------
        // Caso B: LW x4, 8(x2)
        // imm=8, rs1=x2(2), rd=x4(4), opcode LOAD, funct3=010
        // encoding: 0x00812203 (lw x4,8(x2))
        instr_in = 32'h00812203;
        #1;

        check(rs1 == 5'd2, "LW: rs1=2");
        check(rd  == 5'd4, "LW: rd=4");
        check(rs1_data == 32'd200, "LW: rs1_data=200");
        check(imm == 32'd8, "LW: imm=8");
        check(reg_write==1 && mem_read==1 && mem_to_reg==1 && alu_src==1, "LW: control (reg_write, mem_read, mem_to_reg, alu_src)");

        // ------------------------------------------------------------
        // Caso C: SW x1, 12(x2)
        // rs1=x2(2), rs2=x1(1), imm=12, opcode STORE, funct3=010
        // encoding: 0x00112623 (sw x1,12(x2))
        instr_in = 32'h00112623;
        #1;

        check(rs1 == 5'd2, "SW: rs1=2");
        check(rs2 == 5'd1, "SW: rs2=1");
        check(rs1_data == 32'd200, "SW: rs1_data=200");
        check(rs2_data == 32'd100, "SW: rs2_data=100");
        check(imm == 32'd12, "SW: imm=12");
        check(mem_write==1 && alu_src==1, "SW: control (mem_write, alu_src)");

        // ------------------------------------------------------------
        // Caso D: BEQ x1, x2, +16
        // encoding típico para +16: 0x00208863 (beq x1,x2,16)
        // (si tu assembler da otro, no importa: acá validamos que sea BRANCH y que imm salga bien)
        instr_in = 32'h00208863;
        #1;

        check(branch==1 && alu_op==2'b01, "BEQ: control (branch, alu_op=01)");
        // El imm debería ser 16 si el encoding es correcto
        check(imm == 32'd16, "BEQ: imm=16 (si el encoding coincide)");

        $display("Fin TB ID stage.");
        $stop;
    end

endmodule
