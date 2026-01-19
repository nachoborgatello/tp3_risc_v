`timescale 1ns / 1ps

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);

    wire [6:0] opcode = instr[6:0];

    // opcodes RV32I
    localparam [6:0] OP_IMM  = 7'b0010011; // I-type ALU immediate
    localparam [6:0] LOAD    = 7'b0000011; // I-type loads
    localparam [6:0] JALR    = 7'b1100111; // I-type jalr
    localparam [6:0] STORE   = 7'b0100011; // S-type
    localparam [6:0] BRANCH  = 7'b1100011; // B-type
    localparam [6:0] LUI     = 7'b0110111; // U-type
    localparam [6:0] AUIPC   = 7'b0010111; // U-type
    localparam [6:0] JAL     = 7'b1101111; // J-type

    always @(*) begin
        case (opcode)

            // I-type: imm[11:0] = instr[31:20], sign-extended
            OP_IMM, LOAD, JALR: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            // S-type: imm[11:5]=instr[31:25], imm[4:0]=instr[11:7], sign-extended
            STORE: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-type:
            // imm[12]=instr[31]
            // imm[11]=instr[7]
            // imm[10:5]=instr[30:25]
            // imm[4:1]=instr[11:8]
            // imm[0]=0
            BRANCH: begin
                imm = {{19{instr[31]}},
                       instr[31],
                       instr[7],
                       instr[30:25],
                       instr[11:8],
                       1'b0};
            end

            // U-type: instr[31:12] << 12
            LUI, AUIPC: begin
                imm = {instr[31:12], 12'b0};
            end

            // J-type:
            // imm[20]=instr[31]
            // imm[19:12]=instr[19:12]
            // imm[11]=instr[20]
            // imm[10:1]=instr[30:21]
            // imm[0]=0
            JAL: begin
                imm = {{11{instr[31]}},
                       instr[31],
                       instr[19:12],
                       instr[20],
                       instr[30:21],
                       1'b0};
            end

            default: begin
                imm = 32'b0;
            end
        endcase
    end

endmodule
