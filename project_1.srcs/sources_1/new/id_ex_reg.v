`timescale 1ns / 1ps

module id_ex_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        write_en,
    input  wire        flush,

    // --------- Entradas DATA ---------
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,

    input  wire [4:0]  rs1_in,
    input  wire [4:0]  rs2_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,
    input  wire [6:0]  funct7_in,

    // --------- Entradas CONTROL (WB / M / EX) ---------
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,

    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        branch_in,

    input  wire        alu_src_in,
    input  wire [1:0]  alu_op_in,

    input  wire        jump_in,
    input  wire        jalr_in,
    input  wire        wb_sel_pc4_in,

    // --------- Salidas DATA ---------
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,

    output reg  [4:0]  rs1_out,
    output reg  [4:0]  rs2_out,
    output reg  [4:0]  rd_out,
    output reg  [2:0]  funct3_out,
    output reg  [6:0]  funct7_out,

    // --------- Salidas CONTROL ---------
    output reg         reg_write_out,
    output reg         mem_to_reg_out,

    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         branch_out,

    output reg         alu_src_out,
    output reg  [1:0]  alu_op_out,

    output reg         jump_out,
    output reg         jalr_out,
    output reg         wb_sel_pc4_out
);

    // Helper: burbuja = controles en 0, datos opcionalmente 0
    task automatic bubble;
    begin
        // data
        pc_out       <= 32'b0;
        pc_plus4_out       <= 32'b0;
        rs1_data_out <= 32'b0;
        rs2_data_out <= 32'b0;
        imm_out      <= 32'b0;

        rs1_out      <= 5'b0;
        rs2_out      <= 5'b0;
        rd_out       <= 5'b0;
        funct3_out   <= 3'b0;
        funct7_out   <= 7'b0;

        // control
        reg_write_out <= 1'b0;
        mem_to_reg_out<= 1'b0;

        mem_read_out  <= 1'b0;
        mem_write_out <= 1'b0;
        branch_out    <= 1'b0;

        alu_src_out   <= 1'b0;
        alu_op_out    <= 2'b00;

        jump_out      <= 1'b0;
        jalr_out      <= 1'b0;
        wb_sel_pc4_out      <= 1'b0;
    end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            bubble();
        end else if (flush) begin
            bubble();
        end else if (write_en) begin
            // DATA
            pc_out       <= pc_in;
            pc_plus4_out <= pc_plus4_in;
            rs1_data_out <= rs1_data_in;
            rs2_data_out <= rs2_data_in;
            imm_out      <= imm_in;

            rs1_out      <= rs1_in;
            rs2_out      <= rs2_in;
            rd_out       <= rd_in;
            funct3_out   <= funct3_in;
            funct7_out   <= funct7_in;

            // CONTROL
            reg_write_out  <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;

            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            branch_out     <= branch_in;

            alu_src_out    <= alu_src_in;
            alu_op_out     <= alu_op_in;

            jump_out       <= jump_in;
            jalr_out       <= jalr_in;
            wb_sel_pc4_out <= wb_sel_pc4_in;
        end
        // else write_en=0 => stall (mantener)
    end

endmodule

