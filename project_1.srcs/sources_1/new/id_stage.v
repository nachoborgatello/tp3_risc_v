`timescale 1ns / 1ps

module id_stage (
    input  wire        clk,
    input  wire        reset,

    // Entradas desde IF/ID
    input  wire [31:0] pc_in,
    input  wire [31:0] instr_in,

    // Interfaz de WB (desde la etapa WB más adelante)
    input  wire        wb_reg_write,
    input  wire [4:0]  wb_rd,
    input  wire [31:0] wb_wd,

    // Campos decodificados (útiles para EX)
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [6:0]  funct7,

    // Salidas principales de ID
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    output wire [31:0] imm,
    output wire [31:0] pc_out,

    // Señales de control principales (Main Control)
    output wire        reg_write,
    output wire        mem_read,
    output wire        mem_write,
    output wire        mem_to_reg,
    output wire        alu_src,
    output wire        branch,
    output wire        jump,
    output wire        jalr,
    output wire        wb_sel_pc4,
    output wire [1:0]  alu_op
);

    // ----------- Field Extractor -----------
    assign opcode = instr_in[6:0];
    assign rd     = instr_in[11:7];
    assign funct3 = instr_in[14:12];
    assign rs1    = instr_in[19:15];
    assign rs2    = instr_in[24:20];
    assign funct7 = instr_in[31:25];

    // ----------- Register File -----------
    // 2 lecturas combinacionales + 1 escritura síncrona desde WB
    regfile u_rf (
        .clk   (clk),
        .reset (reset),
        .we    (wb_reg_write),
        .rs1   (rs1),
        .rs2   (rs2),
        .rd    (wb_rd),
        .wd    (wb_wd),
        .rd1   (rs1_data),
        .rd2   (rs2_data)
    );

    // ----------- Immediate Generator -----------
    imm_gen u_imm (
        .instr(instr_in),
        .imm  (imm)
    );

    // ----------- Main Control Unit -----------
    control_unit u_ctrl (
        .opcode     (opcode),
        .reg_write  (reg_write),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .alu_src    (alu_src),
        .branch     (branch),
        .jump       (jump),
        .jalr       (jalr),
        .wb_sel_pc4 (wb_sel_pc4),
        .alu_op     (alu_op)
    );
    
    // ----------- Program Counter -----------
    assign pc_out = pc_in;
    
endmodule
