`timescale 1ns/1ps

module tb_if_stage;

    localparam XLEN = 32;
    localparam IM_DEPTH = 64;
    localparam integer AW = $clog2(IM_DEPTH);

    reg clk, reset;

    reg              pc_en;
    reg              pcsrc;
    reg [XLEN-1:0]   branch_target;

    reg              imem_dbg_we;
    reg [XLEN-1:0]   imem_dbg_addr;
    reg [31:0]       imem_dbg_wdata;

    reg              dbg_load_pc;
    reg [XLEN-1:0]   dbg_pc_value;

    wire [XLEN-1:0]  pc;
    wire [XLEN-1:0]  pc_plus4;
    wire [31:0]      instr;

    if_stage #(
        .XLEN(XLEN),
        .IM_DEPTH(IM_DEPTH),
        .IMEM_FILE("")
    ) dut (
        .clk(clk),
        .reset(reset),

        .pc_en(pc_en),
        .pcsrc(pcsrc),
        .branch_target(branch_target),

        .imem_dbg_we(imem_dbg_we),
        .imem_dbg_addr(imem_dbg_addr),
        .imem_dbg_wdata(imem_dbg_wdata),

        .dbg_load_pc(dbg_load_pc),
        .dbg_pc_value(dbg_pc_value),

        .pc(pc),
        .pc_plus4(pc_plus4),
        .instr(instr)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task expect32;
        input [31:0] got;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%h exp=%h (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %h (t=%0t)", msg, got, $time);
            end
        end
    endtask

    task expectXLEN;
        input [XLEN-1:0] got;
        input [XLEN-1:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%h exp=%h (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %h (t=%0t)", msg, got, $time);
            end
        end
    endtask

    task imem_write_word;
        input [XLEN-1:0] byte_addr;
        input [31:0]     wdata;
        reg [AW-1:0]     idx;
        begin
            idx = byte_addr[AW+1:2];

            @(negedge clk);
            imem_dbg_addr  = byte_addr;
            imem_dbg_wdata = wdata;
            imem_dbg_we    = 1'b1;

            @(posedge clk);
            @(posedge clk);

            imem_dbg_we    = 1'b0;

            #1;
            if (dut.u_imem.mem[idx] !== wdata) begin
                $display("[FAIL] IMEM write | mem[%0d]=%h exp=%h (t=%0t)",
                         idx, dut.u_imem.mem[idx], wdata, $time);
                $fatal;
            end else begin
                $display("[ OK ] IMEM write | mem[%0d]=%h (t=%0t)",
                         idx, dut.u_imem.mem[idx], $time);
            end
        end
    endtask

    task dbg_force_pc;
        input [XLEN-1:0] new_pc;
        begin
            @(negedge clk);
            dbg_pc_value = new_pc;
            dbg_load_pc  = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            dbg_load_pc  = 1'b0;
            #1;
        end
    endtask

    reg [31:0]  mem_before;
    reg [AW-1:0] idx_mon;

    always @(posedge clk) begin
        idx_mon = imem_dbg_addr[AW+1:2];
        mem_before = dut.u_imem.mem[idx_mon];

        $display("[MON] t=%0t we=%b addr=%h idx=%0d wdata=%h | mem_before=%h",
                 $time, imem_dbg_we, imem_dbg_addr, idx_mon, imem_dbg_wdata, mem_before);
        #0;
        $display("[MON] t=%0t mem_after=%h", $time, dut.u_imem.mem[idx_mon]);
    end

    initial begin
        reset = 1;
        pc_en = 0;
        pcsrc = 0;
        branch_target = 0;

        imem_dbg_we = 0;
        imem_dbg_addr = 0;
        imem_dbg_wdata = 0;

        dbg_load_pc = 0;
        dbg_pc_value = 0;

        @(posedge clk);
        @(posedge clk);
        expectXLEN(pc, 32'h0000_0000, "PC luego de reset");
        reset = 0;

        imem_write_word(32'h0000_0000, 32'h1111_1111);
        imem_write_word(32'h0000_0004, 32'h2222_2222);
        imem_write_word(32'h0000_0008, 32'h3333_3333);
        imem_write_word(32'h0000_0040, 32'hAAAA_0040);

        dbg_force_pc(32'h0000_0000);
        expectXLEN(pc, 32'h0000_0000, "PC forzado a 0 por dbg_load_pc");

        pc_en = 1;
        pcsrc = 0;

        #1;
        expect32(instr, 32'h1111_1111, "Instr leida en PC=0");
        expectXLEN(pc_plus4, 32'h0000_0004, "pc_plus4 en PC=0");

        @(posedge clk); #1;
        expectXLEN(pc, 32'h0000_0004, "PC avanza a 4");
        expect32(instr, 32'h2222_2222, "Instr leida en PC=4");

        @(posedge clk); #1;
        expectXLEN(pc, 32'h0000_0008, "PC avanza a 8");
        expect32(instr, 32'h3333_3333, "Instr leida en PC=8");

        pc_en = 0;
        @(posedge clk); #1;
        expectXLEN(pc, 32'h0000_0008, "STALL: PC se mantiene (1)");
        @(posedge clk); #1;
        expectXLEN(pc, 32'h0000_0008, "STALL: PC se mantiene (2)");
        pc_en = 1;

        branch_target = 32'h0000_0040;
        pcsrc = 1;
        @(posedge clk); #1;
        expectXLEN(pc, 32'h0000_0040, "BRANCH: PC salta a 0x40");
        expect32(instr, 32'hAAAA_0040, "Instr leida en PC=0x40");
        pcsrc = 0;

        @(posedge clk); #1;
        expectXLEN(pc, 32'h0000_0044, "PC continua a 0x44 (PC+4)");

        pc_en = 0;
        dbg_force_pc(32'h0000_0004);
        expectXLEN(pc, 32'h0000_0004, "dbg_load_pc pisa (con pc_en=0)");

        $display("========================================");
        $display("FIN: tb_if_stage OK");
        $display("========================================");
        $finish;
    end

endmodule
