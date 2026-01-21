`timescale 1ns/1ps

module tb_imm_gen;

    reg  [31:0] instr;
    wire [31:0] imm;

    imm_gen dut (
        .instr(instr),
        .imm(imm)
    );

    task expect32;
        input [31:0] got;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%h exp=%h", msg, got, exp);
                $fatal;
            end else begin
                $display("[ OK ] %s | %h", msg, got);
            end
        end
    endtask

    initial begin
        // I-type: opcode=0010011, imm=+5
        instr = 32'b0;
        instr[6:0]   = 7'b0010011;
        instr[31:20] = 12'd5;
        #1;
        expect32(imm, 32'd5, "I-type imm=+5");

        // I-type: imm=-1 (0xFFF)
        instr = 32'b0;
        instr[6:0]   = 7'b0000011; // LOAD también es I-type
        instr[31:20] = 12'hFFF;
        #1;
        expect32(imm, 32'hFFFF_FFFF, "I-type imm=-1");

        // S-type: opcode=0100011, imm=+12
        instr = 32'b0;
        instr[6:0]   = 7'b0100011;
        // imm[11:5]=0, imm[4:0]=12
        instr[11:7]  = 5'd12;
        instr[31:25] = 7'd0;
        #1;
        expect32(imm, 32'd12, "S-type imm=+12");

        // B-type: opcode=1100011, imm=+16
        // +16 => 0b0000000010000 (bit0=0), imm[4:1]=1000, imm[11]=0, imm[12]=0, imm[10:5]=0
        instr = 32'b0;
        instr[6:0]   = 7'b1100011;
        instr[11:8]  = 4'b1000; // imm[4:1]
        instr[30:25] = 6'b000000;
        instr[7]     = 1'b0;    // imm[11]
        instr[31]    = 1'b0;    // imm[12]
        #1;
        expect32(imm, 32'd16, "B-type imm=+16");

        // U-type: LUI, imm=0x12345000
        instr = 32'b0;
        instr[6:0]   = 7'b0110111;
        instr[31:12] = 20'h12345;
        #1;
        expect32(imm, 32'h1234_5000, "U-type imm");

        // J-type: opcode=1101111, imm=+2048 (0x800)
        instr = 32'b0;
        instr[6:0]   = 7'b1101111;
        instr[31]    = 1'b0;    // imm[20]
        instr[19:12] = 8'b0;    // imm[19:12]
        instr[20]    = 1'b1;    // imm[11] = 1  => 0x800
        instr[30:21] = 10'b0;   // imm[10:1]
        #1;
        expect32(imm, 32'd2048, "J-type imm=+2048");

        $display("========================================");
        $display("FIN: tb_imm_gen OK");
        $display("========================================");
        $finish;
    end

endmodule
