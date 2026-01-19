`timescale 1ns / 1ps

module ex_stage (
    // Data desde ID/EX
    input  wire [31:0] pc_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,

    // Control / fields desde ID/EX
    input  wire        alu_src_in,
    input  wire [1:0]  alu_op_in,
    input  wire [2:0]  funct3_in,
    input  wire [6:0]  funct7_in,
    input  wire        branch_in,
    input  wire        jump,
    input  wire        jalr,

    // Salidas hacia EX/MEM
    output wire [31:0] alu_result_out,
    output wire [31:0] rs2_pass_out,
    output wire [31:0] branch_target_out,
    
    output wire [31:0] jal_target_ex,
    output wire [31:0] jalr_target_ex,
    
    output wire        branch_taken_out,

    // Flags (útiles para debug y para futuras branches)
    output wire        zero_out,
    output wire        lt_out,
    output wire        ltu_out
);

    // ------------- MUX ALUSrc (solo operando B) -------------
    wire [31:0] alu_b = (alu_src_in) ? imm_in : rs2_data_in;
    wire [31:0] alu_a = rs1_data_in;

    // ------------- ALU Control -------------
    wire [3:0] alu_ctrl;

    alu_control u_aluctrl (
        .alu_op   (alu_op_in),
        .funct3   (funct3_in),
        .funct7   (funct7_in),
        .alu_ctrl (alu_ctrl)
    );

    // ------------- ALU -------------
    wire [31:0] alu_result;
    wire zero, lt, ltu;

    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result),
        .zero     (zero),
        .lt       (lt),
        .ltu      (ltu)
    );

    // ------------- Branch target -------------
    // Para B-type, imm ya viene con bit0=0, así que pc+imm está bien.
    assign branch_target_out = pc_in + imm_in;

    assign jal_target_ex = pc_in + imm_in;
    assign jalr_target_ex = (rs1_data_in + imm_in) & 32'hFFFF_FFFE;

    // ------------- Branch decision (solo BEQ/BNE por ahora) -------------
    // funct3:
    // 000 = BEQ
    // 001 = BNE
    
    wire eq = (rs1_data_in == rs2_data_in);
    
    wire cond_true =
        (funct3_in == 3'b000) ?  eq  :   // BEQ
        (funct3_in == 3'b001) ? ~eq  :   // BNE
        1'b0;
    
    assign branch_taken_out = branch_in & cond_true;

    // ------------- Salidas -------------
    assign alu_result_out = alu_result;
    assign rs2_pass_out   = rs2_data_in;

    assign zero_out = zero;
    assign lt_out   = lt;
    assign ltu_out  = ltu;

endmodule
