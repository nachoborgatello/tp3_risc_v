`timescale 1ns / 1ps
`default_nettype none

module cpu_top #(
    parameter IMEM_FILE = "",
    parameter DMEM_FILE = ""
)(
    input  wire clk,
    input  wire reset,

    input  wire        dbg_freeze,
    input  wire        dbg_flush_pipe,
    input  wire        dbg_load_pc,
    input  wire [31:0] dbg_pc_value,

    input  wire        imem_dbg_we,
    input  wire [31:0] imem_dbg_addr,
    input  wire [31:0] imem_dbg_wdata,

    input  wire        dbg_run,
    input  wire        dbg_step,
    input  wire        dbg_drain,

    output wire        dbg_pipe_empty,
    output wire        dbg_halt_seen,

    output wire [31:0]       dbg_pc,
    //output wire [32*32-1:0]  dbg_regs_flat,
    //output wire [64*8-1:0]   dbg_dmem_flat,
    output wire [23*32-1:0] dbg_pipe_flat,
    
    // DEBUG stream ports
    input  wire [4:0]  rf_dbg_addr,
    output wire [31:0] rf_dbg_data,
    input  wire [11:0] dmem_dbg_addr,
    output wire [7:0]  dmem_dbg_data
);

    // ----------------------------
    // Global wires/regs
    // ----------------------------
    reg  dbg_step_q;
    wire step_pulse, step_fire, cpu_ce;

    wire [31:0] pc_if, pc_plus4_if, instr_if;

    wire [31:0] pc_ifid, pc_plus4_ifid, instr_ifid;
    wire        valid_ifid;

    wire        hdu_pc_en, hdu_ifid_we, hdu_idex_flush;

    wire [31:0] pc_id, rs1_data_id, rs2_data_id, imm_id;
    wire [6:0]  opcode_id, funct7_id;
    wire [4:0]  rs1_id, rs2_id, rd_id;
    wire [2:0]  funct3_id;

    wire        reg_write_id, mem_to_reg_id;
    wire        mem_read_id, mem_write_id, branch_id;
    wire        alu_src_id;
    wire [1:0]  alu_op_id;
    wire        jump_id, jalr_id, wb_sel_pc4_id;

    wire [31:0] wb_wd;
    wire        wb_we;
    wire [4:0]  wb_rd;

    wire [31:0] pc_idex, pc_plus4_idex, rs1_data_idex, rs2_data_idex, imm_idex;
    wire        valid_idex;
    wire [4:0]  rs1_idex, rs2_idex, rd_idex;
    wire [2:0]  funct3_idex;
    wire [6:0]  funct7_idex;

    wire        reg_write_idex, mem_to_reg_idex;
    wire        mem_read_idex, mem_write_idex, branch_idex;
    wire        alu_src_idex;
    wire [1:0]  alu_op_idex;
    wire        jump_idex, jalr_idex, wb_sel_pc4_idex;

    wire [1:0]  forward_a, forward_b;
    reg  [31:0] rs1_fwd, rs2_fwd;

    wire [31:0] alu_result_ex, rs2_pass_ex, branch_target_ex;
    wire        branch_taken_ex;
    wire        zero_ex, lt_ex, ltu_ex;
    wire [31:0] jal_target_ex, jalr_target_ex;

    wire        pcsrc_ex;
    wire [31:0] pc_branch_ex;

    wire [31:0] alu_result_exmem, rs2_pass_exmem, branch_target_exmem, pc_plus4_exmem;
    wire [4:0]  rd_exmem;
    wire [2:0]  funct3_exmem;
    wire        mem_read_exmem, mem_write_exmem;
    wire        reg_write_exmem, mem_to_reg_exmem, wb_sel_pc4_exmem;
    wire        valid_exmem;
    wire        branch_taken_exmem;

    wire [31:0] mem_read_data_mem, alu_result_mem;

    wire [31:0] mem_read_data_mwb, alu_result_mwb, pc_plus4_mwb;
    wire        valid_memwb;
    wire [4:0]  rd_mwb;
    wire        reg_write_mwb, mem_to_reg_mwb, wb_sel_pc4_mwb;

    wire        pc_en, write_ifid, flush_ifid, flush_idex;
    wire        write_idex, write_exmem, write_memwb;

    // ----------------------------
    // Debug run/step/drain gating
    // ----------------------------
    always @(posedge clk) begin
        if (reset) dbg_step_q <= 1'b0;
        else       dbg_step_q <= dbg_step;
    end

    assign step_pulse = dbg_step & ~dbg_step_q;
    assign step_fire  = step_pulse & ~dbg_run;

    assign cpu_ce = (dbg_run | step_fire | dbg_drain) & ~dbg_freeze;

    // ----------------------------
    // Halt detect
    // ----------------------------
    localparam [31:0] INSTR_EBREAK = 32'h0010_0073;
    wire halt_id = valid_ifid && (instr_ifid == INSTR_EBREAK);

    reg halt_seen_r;
    always @(posedge clk) begin
        if (reset) begin
            halt_seen_r <= 1'b0;
        end else if (dbg_flush_pipe || dbg_load_pc) begin
            halt_seen_r <= 1'b0;
        end else if (halt_id) begin
            halt_seen_r <= 1'b1;
        end
    end
    assign dbg_halt_seen = halt_seen_r;

    // ----------------------------
    // Pipe empty
    // ----------------------------
    assign dbg_pipe_empty = ~(valid_ifid | valid_idex | valid_exmem | valid_memwb);

    // ----------------------------
    // IF
    // ----------------------------
    assign pc_en = hdu_pc_en & cpu_ce & ~dbg_drain;

    if_stage #(
        .IMEM_FILE(IMEM_FILE)
    ) u_if (
        .clk(clk),
        .reset(reset),

        .pc_en(pc_en),
        .pcsrc(pcsrc_ex),
        .branch_target(pc_branch_ex),

        .imem_dbg_we(imem_dbg_we),
        .imem_dbg_addr(imem_dbg_addr),
        .imem_dbg_wdata(imem_dbg_wdata),

        .dbg_load_pc(dbg_load_pc),
        .dbg_pc_value(dbg_pc_value),

        .pc(pc_if),
        .pc_plus4(pc_plus4_if),
        .instr(instr_if)
    );

    // ----------------------------
    // IF/ID
    // ----------------------------
    assign flush_ifid = ((pcsrc_ex & cpu_ce) | dbg_flush_pipe) | dbg_drain;
    assign write_ifid = hdu_ifid_we & cpu_ce;

    if_id_reg u_ifid (
        .clk(clk),
        .reset(reset),
        .write_en(write_ifid),
        .flush(flush_ifid),

        .pc_in(pc_if),
        .pc_plus4_in(pc_plus4_if),
        .instr_in(instr_if),

        .valid_in(pc_en & ~dbg_drain),
        .valid_out(valid_ifid),

        .pc_out(pc_ifid),
        .pc_plus4_out(pc_plus4_ifid),
        .instr_out(instr_ifid)
    );

    // ----------------------------
    // HDU
    // ----------------------------
    hazard_detection_unit u_hdu (
        .idex_mem_read(mem_read_idex),
        .idex_rd      (rd_idex),
        .ifid_rs1     (instr_ifid[19:15]),
        .ifid_rs2     (instr_ifid[24:20]),
        .pc_en        (hdu_pc_en),
        .ifid_write_en(hdu_ifid_we),
        .idex_flush   (hdu_idex_flush)
    );

    // ----------------------------
    // ID
    // ----------------------------
    id_stage u_id (
        .clk(clk),
        .reset(reset),

        .pc_in(pc_ifid),
        .instr_in(instr_ifid),

        .wb_reg_write(wb_we & cpu_ce),
        .wb_rd(wb_rd),
        .wb_wd(wb_wd),

        .opcode(opcode_id),
        .rd(rd_id),
        .funct3(funct3_id),
        .rs1(rs1_id),
        .rs2(rs2_id),
        .funct7(funct7_id),

        .rs1_data(rs1_data_id),
        .rs2_data(rs2_data_id),
        .imm(imm_id),
        .pc_out(pc_id),

        .reg_write(reg_write_id),
        .mem_read(mem_read_id),
        .mem_write(mem_write_id),
        .mem_to_reg(mem_to_reg_id),
        .alu_src(alu_src_id),
        .branch(branch_id),
        .jump(jump_id),
        .jalr(jalr_id),
        .wb_sel_pc4(wb_sel_pc4_id),
        .alu_op(alu_op_id),
        
        .dbg_reg_addr(rf_dbg_addr),
        .dbg_reg_data(rf_dbg_data)
    );

    // ----------------------------
    // ID/EX
    // ----------------------------
    assign flush_idex = (((pcsrc_ex | hdu_idex_flush) & cpu_ce) | dbg_flush_pipe) | dbg_drain;
    assign write_idex = cpu_ce;

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
        .valid_in(valid_ifid),

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
        .valid_out(valid_idex),

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

    // ----------------------------
    // Forwarding
    // ----------------------------
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

    always @(*) begin
        rs1_fwd = rs1_data_idex;
        rs2_fwd = rs2_data_idex;

        case (forward_a)
            2'b01: rs1_fwd = wb_wd;
            2'b10: rs1_fwd = alu_result_exmem;
            default: rs1_fwd = rs1_data_idex;
        endcase

        case (forward_b)
            2'b01: rs2_fwd = wb_wd;
            2'b10: rs2_fwd = alu_result_exmem;
            default: rs2_fwd = rs2_data_idex;
        endcase
    end

    // ----------------------------
    // EX
    // ----------------------------
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

        .jal_target_ex(jal_target_ex),
        .jalr_target_ex(jalr_target_ex),

        .branch_taken_out(branch_taken_ex),

        .zero_out(zero_ex),
        .lt_out(lt_ex),
        .ltu_out(ltu_ex)
    );

    assign pcsrc_ex = branch_taken_ex | jump_idex | jalr_idex;

    assign pc_branch_ex =
        (jalr_idex) ? jalr_target_ex :
        (jump_idex) ? jal_target_ex  :
                      branch_target_ex;

    // ----------------------------
    // EX/MEM
    // ----------------------------
    assign write_exmem = cpu_ce;

    ex_mem_reg u_exmem (
        .clk(clk),
        .reset(reset),
        .write_en(write_exmem),
        .flush(1'b0),

        .pc_plus4_in(pc_plus4_idex),

        .alu_result_in(alu_result_ex),
        .rs2_pass_in(rs2_pass_ex),
        .branch_target_in(branch_target_ex),
        .rd_in(rd_idex),
        .funct3_in(funct3_idex),

        .mem_read_in(mem_read_idex),
        .mem_write_in(mem_write_idex),

        .reg_write_in(reg_write_idex),
        .mem_to_reg_in(mem_to_reg_idex),

        .wb_sel_pc4_in(wb_sel_pc4_idex),

        .branch_taken_in(branch_taken_ex),
        .valid_in(valid_idex),

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
        .wb_sel_pc4_out(wb_sel_pc4_exmem),
        .valid_out(valid_exmem)
    );

    // ----------------------------
    // MEM
    // ----------------------------
    mem_stage #(
        .DM_BYTES(1024),
        .DM_FILE(DMEM_FILE)
    ) u_mem (
        .clk(clk),
        .mem_read (mem_read_exmem  & cpu_ce),
        .mem_write(mem_write_exmem & cpu_ce),
        .funct3(funct3_exmem),
        .alu_result_in(alu_result_exmem),
        .write_data(rs2_pass_exmem),
        .mem_read_data(mem_read_data_mem),
        .alu_result_out(alu_result_mem),
        
        .dbg_byte_addr(dmem_dbg_addr),
        .dbg_byte_data(dmem_dbg_data)
    );

    // ----------------------------
    // MEM/WB
    // ----------------------------
    assign write_memwb = cpu_ce;

    mem_wb_reg u_memwb (
        .clk(clk),
        .reset(reset),
        .write_en(write_memwb),
        .flush(1'b0),

        .mem_read_data_in(mem_read_data_mem),
        .alu_result_in(alu_result_mem),
        .rd_in(rd_exmem),

        .reg_write_in(reg_write_exmem),
        .mem_to_reg_in(mem_to_reg_exmem),

        .pc_plus4_in(pc_plus4_exmem),
        .wb_sel_pc4_in(wb_sel_pc4_exmem),
        .valid_in(valid_exmem),

        .mem_read_data_out(mem_read_data_mwb),
        .alu_result_out(alu_result_mwb),
        .rd_out(rd_mwb),

        .reg_write_out(reg_write_mwb),
        .mem_to_reg_out(mem_to_reg_mwb),

        .pc_plus4_out(pc_plus4_mwb),
        .wb_sel_pc4_out(wb_sel_pc4_mwb),
        .valid_out(valid_memwb)
    );

    // ----------------------------
    // WB
    // ----------------------------
    wb_stage u_wb (
        .mem_read_data(mem_read_data_mwb),
        .alu_result(alu_result_mwb),
        .pc_plus4_mwb(pc_plus4_mwb),
        .mem_to_reg(mem_to_reg_mwb),
        .reg_write_in(reg_write_mwb),
        .wb_sel_pc4_mwb(wb_sel_pc4_mwb),
        .rd_in(rd_mwb),

        .wb_wd(wb_wd),
        .wb_we(wb_we),
        .wb_rd(wb_rd)
    );
    
    assign dbg_pc = pc_if;

        // ============================================================
    // PIPE DEBUG PACK (23 words)
    // ============================================================
    // IF/ID (4 words)
    wire [31:0] pipe_w0  = pc_ifid;
    wire [31:0] pipe_w1  = pc_plus4_ifid;
    wire [31:0] pipe_w2  = instr_ifid;
    wire [31:0] pipe_w3  = {31'b0, valid_ifid};

    // ID/EX (8 words)
    wire [31:0] pipe_w4  = pc_idex;
    wire [31:0] pipe_w5  = pc_plus4_idex;
    wire [31:0] pipe_w6  = rs1_data_idex;
    wire [31:0] pipe_w7  = rs2_data_idex;
    wire [31:0] pipe_w8  = imm_idex;

    // Fields pack: [31:25]=funct7, [24:22]=funct3, [21:17]=rs2, [16:12]=rs1, [11:7]=rd
    wire [31:0] pipe_w9  = {funct7_idex, funct3_idex, rs2_idex, rs1_idex, rd_idex, 7'b0};

    // Control pack (bits fijos para GUI)
    // bit0  valid_idex
    // bit1  reg_write
    // bit2  mem_to_reg
    // bit3  mem_read
    // bit4  mem_write
    // bit5  branch
    // bit6  alu_src
    // bit8:7  alu_op[1:0]
    // bit9  jump
    // bit10 jalr
    // bit11 wb_sel_pc4
    wire [31:0] pipe_w10 = {
        20'b0,
        wb_sel_pc4_idex, jalr_idex, jump_idex,
        alu_op_idex,
        alu_src_idex, branch_idex, mem_write_idex, mem_read_idex, mem_to_reg_idex, reg_write_idex,
        valid_idex
    };

    // EX/MEM (6 words)
    wire [31:0] pipe_w11 = alu_result_exmem;
    wire [31:0] pipe_w12 = rs2_pass_exmem;
    wire [31:0] pipe_w13 = branch_target_exmem;
    wire [31:0] pipe_w14 = pc_plus4_exmem;

    // Fields pack: rd + funct3
    wire [31:0] pipe_w15 = {19'b0, funct3_exmem, rd_exmem, 5'b0};

    // Control pack
    // bit0  valid_exmem
    // bit1  reg_write
    // bit2  mem_to_reg
    // bit3  mem_read
    // bit4  mem_write
    // bit5  branch_taken
    // bit6  wb_sel_pc4
    wire [31:0] pipe_w16 = {25'b0, wb_sel_pc4_exmem, branch_taken_exmem, mem_write_exmem, mem_read_exmem, mem_to_reg_exmem, reg_write_exmem, valid_exmem};

    // MEM/WB (5 words)
    wire [31:0] pipe_w17 = mem_read_data_mwb;
    wire [31:0] pipe_w18 = alu_result_mwb;
    wire [31:0] pipe_w19 = pc_plus4_mwb;
    wire [31:0] pipe_w20 = {27'b0, rd_mwb};

    // Control pack
    // bit0  valid_memwb
    // bit1  reg_write
    // bit2  mem_to_reg
    // bit3  wb_sel_pc4
    wire [31:0] pipe_w21 = {28'b0, wb_sel_pc4_mwb, mem_to_reg_mwb, reg_write_mwb, valid_memwb};

    // Extra/reservado (por si querés crecer sin romper GUI)
    wire [31:0] pipe_w22 = 32'h0000_0000;

    // IMPORTANT: word0 en [31:0], word1 en [63:32], etc.
    assign dbg_pipe_flat = {
        pipe_w22, pipe_w21, pipe_w20, pipe_w19, pipe_w18, pipe_w17,
        pipe_w16, pipe_w15, pipe_w14, pipe_w13, pipe_w12, pipe_w11,
        pipe_w10, pipe_w9,  pipe_w8,  pipe_w7,  pipe_w6,  pipe_w5, pipe_w4,
        pipe_w3,  pipe_w2,  pipe_w1,  pipe_w0
    };

endmodule

`default_nettype wire
