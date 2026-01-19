`timescale 1ns/1ps

module tb_imm_gen;

    reg  [31:0] instr;
    wire [31:0] imm;

    imm_gen dut (
        .instr(instr),
        .imm(imm)
    );

    task check_imm(input [31:0] i, input [31:0] expected, input [127:0] name);
    begin
        instr = i;
        #1;
        if (imm !== expected) begin
            $display("ERROR %0s: imm=%h esperado=%h instr=%h", name, imm, expected, instr);
        end else begin
            $display("OK    %0s: imm=%h", name, imm);
        end
    end
    endtask

    initial begin
        // ADDI x1,x0,5  => imm = 5
        // encoding: imm[11:0]=5, rs1=0, funct3=000, rd=1, opcode=0010011
        check_imm(32'h00500093, 32'd5, "ADDI x1,x0,5");

        // LW x2,8(x0) => imm = 8
        // imm=8, rs1=0, funct3=010, rd=2, opcode=0000011
        check_imm(32'h00802103, 32'd8, "LW x2,8(x0)");

        // SW x2,12(x0) => imm = 12
        // imm=12 -> [11:5]=0, [4:0]=12, rs2=2, rs1=0, funct3=010, opcode=0100011
        check_imm(32'h00202623, 32'd12, "SW x2,12(x0)");

        // BEQ x0,x0,+16 => imm = 16
        // Para +16: imm[4:1]=1000, imm[10:5]=000000, imm[11]=0, imm[12]=0
        // encoding result:
        check_imm(32'h00000863, 32'd16, "BEQ x0,x0,+16");

        // LUI x3,0x12345 => imm = 0x12345000
        // instr = 0x12345 << 12 | rd=3 | opcode=0110111
        check_imm(32'h123451B7, 32'h12345000, "LUI x3,0x12345");

        // JAL x0,+32 => imm = 32
        // encoding para +32 (bit0=0):
        check_imm(32'h0200006F, 32'd32, "JAL x0,+32");

        $display("Fin TB imm_gen.");
        $stop;
    end

endmodule
