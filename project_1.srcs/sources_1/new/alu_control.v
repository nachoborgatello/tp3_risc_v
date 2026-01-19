`timescale 1ns / 1ps

// Genera la señal de control de la ALU a partir de ALUOp, funct3 y funct7

module alu_control (
    input  wire [1:0] alu_op,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [3:0] alu_ctrl
);

    // ALU control codes
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

    always @(*) begin
        case (alu_op)

            // Loads / Stores / AUIPC / JALR
            2'b00: alu_ctrl = ADD;

            // Branches (comparación vía resta)
            2'b01: alu_ctrl = SUB;

            // R-type
            2'b10: begin
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? SUB : ADD; // add / sub
                    3'b111: alu_ctrl = AND;
                    3'b110: alu_ctrl = OR;
                    3'b100: alu_ctrl = XOR;
                    3'b010: alu_ctrl = SLT;
                    3'b011: alu_ctrl = SLTU;
                    3'b001: alu_ctrl = SLL;
                    3'b101: alu_ctrl = (funct7[5]) ? SRA : SRL;
                    default: alu_ctrl = ADD;
                endcase
            end

            // I-type ALU
            2'b11: begin
                case (funct3)
                    3'b000: alu_ctrl = ADD;   // addi
                    3'b111: alu_ctrl = AND;   // andi
                    3'b110: alu_ctrl = OR;    // ori
                    3'b100: alu_ctrl = XOR;   // xori
                    3'b010: alu_ctrl = SLT;   // slti
                    3'b011: alu_ctrl = SLTU;  // sltiu
                    3'b001: alu_ctrl = SLL;   // slli
                    3'b101: alu_ctrl = (funct7[5]) ? SRA : SRL; // srli/srai
                    default: alu_ctrl = ADD;
                endcase
            end

            default: alu_ctrl = ADD;
        endcase
    end

endmodule
