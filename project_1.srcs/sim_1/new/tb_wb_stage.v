`timescale 1ns/1ps

module tb_wb_stage;

    reg [31:0] mem_read_data, alu_result;
    reg        mem_to_reg;
    reg        reg_write_in;
    reg [4:0]  rd_in;

    wire [31:0] wb_wd;
    wire        wb_we;
    wire [4:0]  wb_rd;

    wb_stage dut (
        .mem_read_data(mem_read_data),
        .alu_result(alu_result),
        .mem_to_reg(mem_to_reg),
        .reg_write_in(reg_write_in),
        .rd_in(rd_in),
        .wb_wd(wb_wd),
        .wb_we(wb_we),
        .wb_rd(wb_rd)
    );

    task settle; begin #2; end endtask

    task check32(input [31:0] got, input [31:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
        else            $display("OK    %0s", name);
    end
    endtask

    task check1(input got, input exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%0d exp=%0d", name, got, exp);
        else             $display("OK    %0s", name);
    end
    endtask

    task check5(input [4:0] got, input [4:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%0d exp=%0d", name, got, exp);
        else             $display("OK    %0s", name);
    end
    endtask

    initial begin
        // Inicialización fuerte para evitar X en t=0
        mem_read_data = 32'h0000_0000;
        alu_result    = 32'h0000_0000;
        mem_to_reg    = 1'b0;
        reg_write_in  = 1'b0;
        rd_in         = 5'd0;

        settle();

        // Caso 1: writeback desde ALU
        mem_read_data = 32'hAAAA_AAAA;
        alu_result    = 32'h1234_5678;
        mem_to_reg    = 1'b0;
        reg_write_in  = 1'b1;
        rd_in         = 5'd3;

        settle();
        check32(wb_wd, 32'h1234_5678, "WB from ALU");
        check1 (wb_we, 1'b1,          "WB we pass-through");
        check5 (wb_rd, 5'd3,          "WB rd pass-through");

        // Caso 2: writeback desde memoria
        mem_to_reg = 1'b1;

        settle();
        check32(wb_wd, 32'hAAAA_AAAA, "WB from MEM");

        // Caso 3: reg_write deshabilitado
        reg_write_in = 1'b0;

        settle();
        check1(wb_we, 1'b0, "WB disabled");

        $display("Fin TB WB stage (robusto).");
        $stop;
    end

endmodule
