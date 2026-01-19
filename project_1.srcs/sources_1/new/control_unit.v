`timescale 1ns / 1ps

module control_unit (
    input  wire [6:0] opcode,

    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        mem_to_reg,
    output reg        alu_src,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg        wb_sel_pc4,
    output reg [1:0]  alu_op
);

    // opcodes RV32I
    localparam [6:0] OP      = 7'b0110011; // R-type
    localparam [6:0] OP_IMM  = 7'b0010011; // I-type ALU
    localparam [6:0] LOAD    = 7'b0000011; // lw
    localparam [6:0] STORE   = 7'b0100011; // sw
    localparam [6:0] BRANCH  = 7'b1100011; // beq/bne/...
    localparam [6:0] JAL     = 7'b1101111; // jal
    localparam [6:0] JALR    = 7'b1100111; // jalr
    localparam [6:0] LUI     = 7'b0110111; // lui
    localparam [6:0] AUIPC   = 7'b0010111; // auipc

    always @(*) begin
        // defaults (seguro)
        reg_write  = 0;
        mem_read   = 0;
        mem_write  = 0;
        mem_to_reg = 0;
        alu_src    = 0;
        branch     = 0;
        jump       = 0;
        jalr       = 0;
        wb_sel_pc4 = 0;
        alu_op     = 2'b00;

        case (opcode)

            // R-type: rd = rs1 op rs2
            OP: begin
                reg_write = 1;
                alu_src   = 0;
                alu_op    = 2'b10;
            end

            // I-type ALU: rd = rs1 op imm
            OP_IMM: begin
                reg_write = 1;
                alu_src   = 1;
                alu_op    = 2'b11;
            end

            // LOAD (lw): rd = Mem[rs1 + imm]
            LOAD: begin
                reg_write  = 1;
                mem_read   = 1;
                mem_to_reg = 1;
                alu_src    = 1;
                alu_op     = 2'b00; // suma para dirección
            end

            // STORE (sw): Mem[rs1 + imm] = rs2
            STORE: begin
                mem_write = 1;
                alu_src   = 1;
                alu_op    = 2'b00; // suma para dirección
            end

            // BRANCH: PC = PC + imm si condición
            BRANCH: begin
                branch  = 1;
                alu_src = 0;
                alu_op  = 2'b01;
            end

            // JAL: rd = PC+4 ; PC = PC + imm
            JAL: begin
                reg_write = 1; // escribe link
                jump      = 1;
                wb_sel_pc4 = 1;
                // alu_op no es crítico acá; depende del datapath que armes
            end

            // JALR: rd = PC+4 ; PC = (rs1 + imm) & ~1
            JALR: begin
                reg_write = 1;
                jalr      = 1;
                alu_src   = 1; // rs1 + imm
                wb_sel_pc4 = 1;
                alu_op    = 2'b00; // suma
            end

            // LUI: rd = imm (upper)
            LUI: begin
                reg_write = 1;
                alu_src   = 1;
                // muchos datapaths hacen que ALU "pase B" o sumen con 0
            end

            // AUIPC: rd = PC + imm
            AUIPC: begin
                reg_write = 1;
                alu_src   = 1;
                alu_op    = 2'b00; // suma (PC + imm)
            end

            default: begin
                // todo en 0
            end
        endcase
    end

endmodule
