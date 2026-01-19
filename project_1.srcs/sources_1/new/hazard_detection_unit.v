`timescale 1ns / 1ps

module hazard_detection_unit (
    input  wire        idex_mem_read,
    input  wire [4:0]  idex_rd,
    input  wire [4:0]  ifid_rs1,
    input  wire [4:0]  ifid_rs2,

    output wire        pc_en,
    output wire        ifid_write_en,
    output wire        idex_flush
);

    wire stall;

    assign stall =
        idex_mem_read &&
        (idex_rd != 5'd0) &&
        ((idex_rd == ifid_rs1) || (idex_rd == ifid_rs2));

    // Si stall=1: congelar PC e IF/ID, y flushear ID/EX
    assign pc_en         = ~stall;
    assign ifid_write_en = ~stall;
    assign idex_flush    = stall;

endmodule
