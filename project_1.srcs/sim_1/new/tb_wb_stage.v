`timescale 1ns/1ps

module tb_wb_stage;

    reg [31:0] mem_read_data, alu_result, pc_plus4_mwb;
    reg        mem_to_reg, reg_write_in, wb_sel_pc4_mwb;
    reg [4:0]  rd_in;

    wire [31:0] wb_wd;
    wire        wb_we;
    wire [4:0]  wb_rd;

    wb_stage dut (
        .mem_read_data(mem_read_data),
        .alu_result(alu_result),
        .pc_plus4_mwb(pc_plus4_mwb),
        .mem_to_reg(mem_to_reg),
        .reg_write_in(reg_write_in),
        .wb_sel_pc4_mwb(wb_sel_pc4_mwb),
        .rd_in(rd_in),
        .wb_wd(wb_wd),
        .wb_we(wb_we),
        .wb_rd(wb_rd)
    );

    task expect32;
        input [31:0] got;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%h exp=%h", msg, got, exp);
                $fatal;
            end else begin
                $display("[ OK ] %s | %h", msg, got);
            end
        end
    endtask

    task expect1;
        input got;
        input exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%b exp=%b", msg, got, exp);
                $fatal;
            end else begin
                $display("[ OK ] %s | %b", msg, got);
            end
        end
    endtask

    task expect5;
        input [4:0] got;
        input [4:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%0d exp=%0d", msg, got, exp);
                $fatal;
            end else begin
                $display("[ OK ] %s | %0d", msg, got);
            end
        end
    endtask

    initial begin
        mem_read_data = 32'h1111_1111;
        alu_result    = 32'h2222_2222;
        pc_plus4_mwb  = 32'h3333_3333;
        rd_in         = 5'd7;
        reg_write_in  = 1'b1;

        // Caso 1: wb_sel_pc4 tiene prioridad
        wb_sel_pc4_mwb = 1'b1;
        mem_to_reg     = 1'b1;
        #1;
        expect32(wb_wd, 32'h3333_3333, "WB sel PC+4 prioridad");
        expect1 (wb_we, 1'b1,          "WB we passthrough");
        expect5 (wb_rd, 5'd7,          "WB rd passthrough");

        // Caso 2: mem_to_reg
        wb_sel_pc4_mwb = 1'b0;
        mem_to_reg     = 1'b1;
        #1;
        expect32(wb_wd, 32'h1111_1111, "WB sel MEM");

        // Caso 3: ALU result
        mem_to_reg     = 1'b0;
        #1;
        expect32(wb_wd, 32'h2222_2222, "WB sel ALU");

        // we en 0
        reg_write_in = 1'b0;
        #1;
        expect1(wb_we, 1'b0, "WB we=0");

        $display("========================================");
        $display("FIN: tb_wb_stage OK");
        $display("========================================");
        $finish;
    end

endmodule
