`timescale 1ns / 1ps

module cpu_top #(
    parameter IMEM_FILE = "",
    parameter DMEM_FILE = ""
)(
    input  wire clk,
    input  wire reset,
    
    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_x1,
    output wire [31:0] dbg_x2,
    output wire [31:0] dbg_x3,
    output wire [31:0] dbg_x4,
    output wire [31:0] dbg_x5,
    output wire [31:0] dbg_x6,
    output wire [31:0] dbg_x7,
    output wire [31:0] dbg_x8,
    output wire [31:0] dbg_x9,
    output wire [31:0] dbg_x10,
    output wire [31:0] dbg_x11,
    output wire [31:0] dbg_x12,
    output wire [31:0] dbg_mem_word0
);

    // ============================================================
    // IF
    // ============================================================
    wire [31:0] pc_if, pc_plus4_if;
    wire [31:0] instr_if;

    // Control de PC (sin stalls por ahora)
    wire pc_en;
    
    assign pc_en      = hdu_pc_en;

    // Señales desde EX para control hazard
    wire        pcsrc_ex;
    wire [31:0] pc_branch_ex;

    // Tu if_stage debe leer IMEM_FILE (si tu if_stage no tiene parámetro,
    // pasalo a tu imem_simple dentro de if_stage).
    if_stage #(
        .IMEM_FILE(IMEM_FILE)
    ) u_if (
        .clk(clk),
        .reset(reset),
        .pc_en(pc_en),
        .pcsrc(pcsrc_ex),
        .branch_target(pc_branch_ex),
        .pc(pc_if),
        .pc_plus4(pc_plus4_if),
        .instr(instr_if)
    );

    // ============================================================
    // IF/ID
    // ============================================================
    wire [31:0] pc_ifid, pc_plus4_ifid;
    wire [31:0] instr_ifid;

    // Flush por branch tomado (mata instrucción en IF/ID)
    wire flush_ifid = pcsrc_ex;
    wire write_ifid;
    
    assign write_ifid = hdu_ifid_we;

    if_id_reg u_ifid (
        .clk(clk),
        .reset(reset),
        .write_en(write_ifid),
        .flush(flush_ifid),
        .pc_in(pc_if),
        .pc_plus4_in(pc_plus4_if),
        .instr_in(instr_if),
        .pc_out(pc_ifid),
        .pc_plus4_out(pc_plus4_ifid),
        .instr_out(instr_ifid)
    );
    
    // ============================================================
    // Hazard detection unit
    // ============================================================
    wire hdu_pc_en, hdu_ifid_we, hdu_idex_flush;
    
    hazard_detection_unit u_hdu (
      .idex_mem_read(mem_read_idex),
      .idex_rd      (rd_idex),
      .ifid_rs1     (instr_ifid[19:15]),
      .ifid_rs2     (instr_ifid[24:20]),
      .pc_en        (hdu_pc_en),
      .ifid_write_en(hdu_ifid_we),
      .idex_flush   (hdu_idex_flush)
    );

    // ============================================================
    // ID
    // ============================================================
    wire [31:0] pc_id;
    wire [31:0] rs1_data_id, rs2_data_id, imm_id;

    wire [4:0]  rs1_id, rs2_id, rd_id;
    wire [2:0]  funct3_id;
    wire [6:0]  funct7_id;

    // Control signals desde control unit (en ID)
    wire        reg_write_id, mem_to_reg_id;
    wire        mem_read_id, mem_write_id, branch_id;
    wire        alu_src_id;
    wire [1:0]  alu_op_id;
    wire        jump_id, jalr_id, wb_sel_pc4_id;

    // Señales WB que vuelven al regfile (desde WB stage)
    wire [31:0] wb_wd;
    wire        wb_we;
    wire [4:0]  wb_rd;

    id_stage u_id (
        .clk(clk),
        .reset(reset),

        .pc_in(pc_ifid),
        .instr_in(instr_ifid),

        .wb_reg_write(wb_we),
        .wb_rd(wb_rd),
        .wb_wd(wb_wd),

        .pc_out(pc_id),
        .rs1_data(rs1_data_id),
        .rs2_data(rs2_data_id),
        .imm(imm_id),

        .rs1(rs1_id),
        .rs2(rs2_id),
        .rd(rd_id),
        .funct3(funct3_id),
        .funct7(funct7_id),

        .reg_write(reg_write_id),
        .mem_to_reg(mem_to_reg_id),

        .mem_read(mem_read_id),
        .mem_write(mem_write_id),
        .branch(branch_id),

        .alu_src(alu_src_id),
        .alu_op(alu_op_id),

        .jump(jump_id),
        .jalr(jalr_id),
        .wb_sel_pc4(wb_sel_pc4_id)
    );

    // ============================================================
    // ID/EX
    // ============================================================
    wire flush_idex;
    
    assign flush_idex = pcsrc_ex | hdu_idex_flush;
    
    wire write_idex = 1'b1;

    wire [31:0] pc_idex, pc_plus4_idex, rs1_data_idex, rs2_data_idex, imm_idex;
    wire [4:0]  rs1_idex, rs2_idex, rd_idex;
    wire [2:0]  funct3_idex;
    wire [6:0]  funct7_idex;

    wire        reg_write_idex, mem_to_reg_idex;
    wire        mem_read_idex, mem_write_idex, branch_idex;
    wire        alu_src_idex;
    wire [1:0]  alu_op_idex;
    wire        jump_idex, jalr_idex, wb_sel_pc4_idex;

    id_ex_reg u_idex (
        .clk(clk),
        .reset(reset),
        .write_en(write_idex),
        .flush(flush_idex),

        .pc_in(pc_id),
        .pc_plus4_in(pc_plus4_ifid),
        .rs1_data_in(rs1_data_id),
        .rs2_data_in(rs2_data_id),
        .imm_in(imm_id),

        .rs1_in(rs1_id),
        .rs2_in(rs2_id),
        .rd_in(rd_id),
        .funct3_in(funct3_id),
        .funct7_in(funct7_id),

        .reg_write_in(reg_write_id),
        .mem_to_reg_in(mem_to_reg_id),

        .mem_read_in(mem_read_id),
        .mem_write_in(mem_write_id),
        .branch_in(branch_id),

        .alu_src_in(alu_src_id),
        .alu_op_in(alu_op_id),

        .jump_in(jump_id),
        .jalr_in(jalr_id),
        .wb_sel_pc4_in(wb_sel_pc4_id),

        .pc_out(pc_idex),
        .pc_plus4_out(pc_plus4_idex),
        .rs1_data_out(rs1_data_idex),
        .rs2_data_out(rs2_data_idex),
        .imm_out(imm_idex),

        .rs1_out(rs1_idex),
        .rs2_out(rs2_idex),
        .rd_out(rd_idex),
        .funct3_out(funct3_idex),
        .funct7_out(funct7_idex),

        .reg_write_out(reg_write_idex),
        .mem_to_reg_out(mem_to_reg_idex),

        .mem_read_out(mem_read_idex),
        .mem_write_out(mem_write_idex),
        .branch_out(branch_idex),

        .alu_src_out(alu_src_idex),
        .alu_op_out(alu_op_idex),

        .jump_out(jump_idex),
        .jalr_out(jalr_idex),
        .wb_sel_pc4_out(wb_sel_pc4_idex)
    );
    // ============================================================
    // Forwarding Unit
    // ============================================================
    wire [1:0] forward_a, forward_b;
    
    forwarding_unit u_fwd (
        .exmem_reg_write(reg_write_exmem),
        .exmem_rd       (rd_exmem),
        .memwb_reg_write(reg_write_mwb),
        .memwb_rd       (rd_mwb),
        .idex_rs1       (rs1_idex),
        .idex_rs2       (rs2_idex),
        .forward_a      (forward_a),
        .forward_b      (forward_b)
    );
    
    reg [31:0] rs1_fwd, rs2_fwd;

    always @(*) begin
      // defaults
      rs1_fwd = rs1_data_idex;
      rs2_fwd = rs2_data_idex;
    
      // Operando A (rs1)
      case (forward_a)
        2'b00: rs1_fwd = rs1_data_idex;
        2'b01: rs1_fwd = wb_wd;             // MEM/WB (dato final de WB)
        2'b10: rs1_fwd = alu_result_exmem;  // EX/MEM (resultado ALU previo)
        default: rs1_fwd = rs1_data_idex;
      endcase
    
      // Operando B "de registro" (rs2)
      case (forward_b)
        2'b00: rs2_fwd = rs2_data_idex;
        2'b01: rs2_fwd = wb_wd;
        2'b10: rs2_fwd = alu_result_exmem;
        default: rs2_fwd = rs2_data_idex;
      endcase
    end
    
    // ============================================================
    // EX
    // ============================================================
    wire [31:0] alu_result_ex;
    wire [31:0] rs2_pass_ex;
    wire [31:0] branch_target_ex;
    wire        branch_taken_ex;
    wire        zero_ex, lt_ex, ltu_ex;
    wire [31:0] jal_target_ex;
    wire [31:0] jalr_target_ex;

    ex_stage u_ex (
        .pc_in(pc_idex),
        .rs1_data_in(rs1_fwd),
        .rs2_data_in(rs2_fwd),
        .imm_in(imm_idex),

        .alu_src_in(alu_src_idex),
        .alu_op_in(alu_op_idex),
        .funct3_in(funct3_idex),
        .funct7_in(funct7_idex),
        .branch_in(branch_idex),
        
        .jump(jump_idex),
        .jalr(jalr_idex),

        .alu_result_out(alu_result_ex),
        .rs2_pass_out(rs2_pass_ex),
        .branch_target_out(branch_target_ex),
        .branch_taken_out(branch_taken_ex),
        
        .jal_target_ex(jal_target_ex),
        .jalr_target_ex(jalr_target_ex),

        .zero_out(zero_ex),
        .lt_out(lt_ex),
        .ltu_out(ltu_ex)
    );

    // PC control (branch en EX)
    assign pcsrc_ex = branch_taken_ex | jump_idex | jalr_idex;
    
    assign pc_branch_ex =
        (jalr_idex) ? jalr_target_ex :
        (jump_idex) ? jal_target_ex  :
                      branch_target_ex;

    // ============================================================
    // EX/MEM
    // ============================================================
    wire        write_exmem = 1'b1;
    wire        flush_exmem = 1'b0; // no lo usamos por ahora

    wire [31:0] alu_result_exmem, rs2_pass_exmem, branch_target_exmem, pc_plus4_exmem;
    wire [4:0]  rd_exmem;
    wire [2:0]  funct3_exmem;

    wire        mem_read_exmem, mem_write_exmem;
    wire        reg_write_exmem, mem_to_reg_exmem, wb_sel_pc4_exmem;
    wire        branch_taken_exmem;

    ex_mem_reg u_exmem (
        .clk(clk),
        .reset(reset),
        .write_en(write_exmem),
        .flush(flush_exmem),
        .pc_plus4_in(pc_plus4_idex),

        .alu_result_in(alu_result_ex),
        .rs2_pass_in(rs2_pass_ex),
        .branch_target_in(branch_target_ex),
        .rd_in(rd_idex),
        
        .wb_sel_pc4_in(wb_sel_pc4_idex),

        .funct3_in(funct3_idex),

        .mem_read_in(mem_read_idex),
        .mem_write_in(mem_write_idex),

        .reg_write_in(reg_write_idex),
        .mem_to_reg_in(mem_to_reg_idex),

        .branch_taken_in(branch_taken_ex),

        .alu_result_out(alu_result_exmem),
        .rs2_pass_out(rs2_pass_exmem),
        .branch_target_out(branch_target_exmem),
        .rd_out(rd_exmem),

        .funct3_out(funct3_exmem),

        .mem_read_out(mem_read_exmem),
        .mem_write_out(mem_write_exmem),

        .reg_write_out(reg_write_exmem),
        .mem_to_reg_out(mem_to_reg_exmem),

        .branch_taken_out(branch_taken_exmem),
        .pc_plus4_out(pc_plus4_exmem),
        .wb_sel_pc4_out(wb_sel_pc4_exmem)
    );

    // ============================================================
    // MEM
    // ============================================================
    wire [31:0] mem_read_data_mem;
    wire [31:0] alu_result_mem;

    mem_stage #(
        .DM_BYTES(4096),
        .DM_FILE(DMEM_FILE)
    ) u_mem (
        .clk(clk),

        .mem_read(mem_read_exmem),
        .mem_write(mem_write_exmem),
        .funct3(funct3_exmem),

        .alu_result_in(alu_result_exmem),
        .write_data(rs2_pass_exmem),

        .mem_read_data(mem_read_data_mem),
        .alu_result_out(alu_result_mem)
    );

    // ============================================================
    // MEM/WB
    // ============================================================
    wire        write_memwb = 1'b1;
    wire        flush_memwb = 1'b0;

    wire [31:0] mem_read_data_mwb, alu_result_mwb, pc_plus4_mwb;
    wire [4:0]  rd_mwb;
    wire        reg_write_mwb, mem_to_reg_mwb, wb_sel_pc4_mwb;

    mem_wb_reg u_memwb (
        .clk(clk),
        .reset(reset),
        .write_en(write_memwb),
        .flush(flush_memwb),

        .mem_read_data_in(mem_read_data_mem),
        .alu_result_in(alu_result_mem),
        .rd_in(rd_exmem),
        .pc_plus4_in(pc_plus4_exmem),
        .wb_sel_pc4_in(wb_sel_pc4_exmem),

        .reg_write_in(reg_write_exmem),
        .mem_to_reg_in(mem_to_reg_exmem),

        .mem_read_data_out(mem_read_data_mwb),
        .alu_result_out(alu_result_mwb),
        .rd_out(rd_mwb),

        .reg_write_out(reg_write_mwb),
        .mem_to_reg_out(mem_to_reg_mwb),
        .pc_plus4_out(pc_plus4_mwb),
        .wb_sel_pc4_out(wb_sel_pc4_mwb)
    );

    // ============================================================
    // WB
    // ============================================================
    wb_stage u_wb (
        .mem_read_data(mem_read_data_mwb),
        .alu_result(alu_result_mwb),
        .mem_to_reg(mem_to_reg_mwb),
        .reg_write_in(reg_write_mwb),
        .rd_in(rd_mwb),
        .pc_plus4_mwb(pc_plus4_mwb),
        .wb_sel_pc4_mwb(wb_sel_pc4_mwb),

        .wb_wd(wb_wd),
        .wb_we(wb_we),
        .wb_rd(wb_rd)
    );
    
    // PC actual (IF)
    assign dbg_pc = pc_if;
    
    // Registros (suponiendo que tu regfile tiene regs[] como array)
    // Ajustá SOLO estas 3 líneas si tu regfile se llama distinto internamente.
    assign dbg_x1 = u_id.u_rf.regs[1];
    assign dbg_x2 = u_id.u_rf.regs[2];
    assign dbg_x3 = u_id.u_rf.regs[3];
    assign dbg_x4 = u_id.u_rf.regs[4];
    assign dbg_x5 = u_id.u_rf.regs[5];
    assign dbg_x6 = u_id.u_rf.regs[6];
    assign dbg_x7 = u_id.u_rf.regs[7];
    assign dbg_x8 = u_id.u_rf.regs[8];
    assign dbg_x9 = u_id.u_rf.regs[9];
    assign dbg_x10 = u_id.u_rf.regs[10];
    assign dbg_x11 = u_id.u_rf.regs[11];
    assign dbg_x12 = u_id.u_rf.regs[12];

    // Memoria de datos: palabra en mem[0..3] (little-endian)
    // Ajustá SOLO el path si tu dmem no se llama igual.
    assign dbg_mem_word0 = {
        u_mem.u_dmem.mem[3],
        u_mem.u_dmem.mem[2],
        u_mem.u_dmem.mem[1],
        u_mem.u_dmem.mem[0]
    };
    
endmodule

