`timescale 1ns / 1ps

module forwarding_unit (
    input  wire        exmem_reg_write,
    input  wire [4:0]  exmem_rd,

    input  wire        memwb_reg_write,
    input  wire [4:0]  memwb_rd,

    input  wire [4:0]  idex_rs1,
    input  wire [4:0]  idex_rs2,

    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b
);

    always @(*) begin
        // default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;

        // -------- Forward A (rs1) --------
        if (exmem_reg_write && (exmem_rd != 5'd0) && (exmem_rd == idex_rs1)) begin
            forward_a = 2'b10; // desde EX/MEM
        end else if (memwb_reg_write && (memwb_rd != 5'd0) && (memwb_rd == idex_rs1)) begin
            forward_a = 2'b01; // desde MEM/WB
        end

        // -------- Forward B (rs2) --------
        if (exmem_reg_write && (exmem_rd != 5'd0) && (exmem_rd == idex_rs2)) begin
            forward_b = 2'b10; // desde EX/MEM
        end else if (memwb_reg_write && (memwb_rd != 5'd0) && (memwb_rd == idex_rs2)) begin
            forward_b = 2'b01; // desde MEM/WB
        end
    end

endmodule

