`timescale 1ns / 1ps

module regfile #(
    parameter XLEN = 32
)(
    input  wire             clk,
    input  wire             reset,      // opcional (limpia regs para sim). Si no lo querés, lo podés quitar.
    input  wire             we,         // write enable
    input  wire [4:0]       rs1,        // read addr 1
    input  wire [4:0]       rs2,        // read addr 2
    input  wire [4:0]       rd,         // write addr
    input  wire [XLEN-1:0]  wd,         // write data
    output wire [XLEN-1:0]  rd1,        // read data 1
    output wire [XLEN-1:0]  rd2         // read data 2
);

    reg [XLEN-1:0] regs [0:31];
    integer i;

    // Escritura sincrónica
    always @(posedge clk) begin
        if (reset) begin
            // Para que la simulación sea limpia y repetible
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= {XLEN{1'b0}};
            end
        end else begin
            // x0 NO se escribe
            if (we && (rd != 5'd0)) begin
                regs[rd] <= wd;
            end
            // opcional: forzar x0 a 0 por seguridad (no es estrictamente necesario)
            regs[0] <= {XLEN{1'b0}};
        end
    end

    // Lecturas combinacionales con write-first logic
    // Si estamos escribiendo en el registro que estamos leyendo, usamos wd
    // De lo contrario, leemos del arreglo de registros
    
    assign rd1 = (rs1 == 5'd0) ? {XLEN{1'b0}} :
                 (we && (rd == rs1) && (rd != 5'd0)) ? wd : regs[rs1];
    
    assign rd2 = (rs2 == 5'd0) ? {XLEN{1'b0}} :
                 (we && (rd == rs2) && (rd != 5'd0)) ? wd : regs[rs2];

endmodule