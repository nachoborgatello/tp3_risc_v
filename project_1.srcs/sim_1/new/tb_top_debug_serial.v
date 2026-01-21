`timescale 1ns/1ps
`default_nettype none

module tb_top_debug_system;

    localparam integer CLK_HZ = 1_843_200;
    localparam integer BAUD   = 115200;
    localparam integer DM_DUMP_BYTES = 64;

    reg clk, reset;

    wire dut_uart_rx;
    wire dut_uart_tx;
    wire s_tick_out;

    top_debug_system #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD),
        .IMEM_FILE(""),
        .DMEM_FILE("")
    ) dut (
        .clk(clk),
        .reset(reset),
        .uart_rx(dut_uart_rx),
        .uart_tx(dut_uart_tx),
        .s_tick_out(s_tick_out)
    );

    // Host UART
    reg        host_tx_start;
    reg  [7:0] host_tx_din;
    wire       host_tx_done_tick;
    wire       host_tx_line;

    wire       host_rx_done_tick;
    wire [7:0] host_rx_dout;

    reg [7:0]  type;
    reg [7:0]  flags;
    reg [31:0] pc_le;

    uart_tx #(.DBIT(8), .SB_TICK(16)) u_host_tx (
        .clk(clk),
        .reset(reset),
        .tx_start(host_tx_start),
        .s_tick(s_tick_out),
        .din(host_tx_din),
        .tx_done_tick(host_tx_done_tick),
        .tx(host_tx_line)
    );

    uart_rx #(.DBIT(8), .SB_TICK(16)) u_host_rx (
        .clk(clk),
        .reset(reset),
        .rx(dut_uart_tx),
        .s_tick(s_tick_out),
        .rx_done_tick(host_rx_done_tick),
        .dout(host_rx_dout)
    );

    assign dut_uart_rx = host_tx_line;

    // Clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------
    // Scoreboard buffers
    // ---------------------------
    reg [31:0] regs_dump [0:31];
    reg [7:0]  mem_dump  [0:DM_DUMP_BYTES-1];

    // ---------------------------
    // Helpers
    // ---------------------------
    task expect8;
        input [7:0] got;
        input [7:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%02h exp=%02h (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %02h (t=%0t)", msg, got, $time);
            end
        end
    endtask

    task expect32;
        input [31:0] got;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            if (got !== exp) begin
                $display("[FAIL] %s | got=%08h exp=%08h (t=%0t)", msg, got, exp, $time);
                $fatal;
            end else begin
                $display("[ OK ] %s | %08h (t=%0t)", msg, got, $time);
            end
        end
    endtask

    task expect_reg;
        input integer ridx;
        input [31:0] exp;
        reg [256*8-1:0] msg;
        begin
            $sformat(msg, "REG x%0d", ridx);
            expect32(regs_dump[ridx], exp, msg);
        end
    endtask

    task expect_mem8;
        input integer midx;
        input [7:0] exp;
        reg [256*8-1:0] msg;
        begin
            $sformat(msg, "DMEM[%0d] byte", midx);
            expect8(mem_dump[midx], exp, msg);
        end
    endtask

    task idle_ticks(input integer nticks);
        integer k;
        begin
            for (k = 0; k < nticks; k = k + 1) @(posedge clk);
        end
    endtask

    task host_send_byte;
        input [7:0] b;
        begin
            @(negedge clk);
            host_tx_din   <= b;
            host_tx_start <= 1'b1;
            @(negedge clk);
            host_tx_start <= 1'b0;

            wait (host_tx_done_tick == 1'b1);
            @(posedge clk);
            idle_ticks(20);
        end
    endtask

    task host_send_u32_le;
        input [31:0] w;
        begin
            host_send_byte(w[7:0]);
            host_send_byte(w[15:8]);
            host_send_byte(w[23:16]);
            host_send_byte(w[31:24]);
        end
    endtask

    task host_recv_byte;
        output [7:0] b;
        integer guard;
        begin
            guard = 0;
            while (host_rx_done_tick !== 1'b1) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 2_000_000) begin
                    $display("[FAIL] timeout esperando rx_done_tick (t=%0t)", $time);
                    $fatal;
                end
            end
            @(posedge clk);
            b = host_rx_dout;
            @(posedge clk);
        end
    endtask

    task recv_dump_header;
        output [7:0]  type;
        output [7:0]  flags;
        output [31:0] pc_le;
        reg [7:0] b;
        begin
            host_recv_byte(b); expect8(b, 8'hD0, "DUMP[0] magic");
            host_recv_byte(type);
            host_recv_byte(flags);
            host_recv_byte(b); expect8(b, 8'h00, "DUMP[3] pad");

            host_recv_byte(b); pc_le[7:0]   = b;
            host_recv_byte(b); pc_le[15:8]  = b;
            host_recv_byte(b); pc_le[23:16] = b;
            host_recv_byte(b); pc_le[31:24] = b;
        end
    endtask

    // Lee payload y lo parsea en regs_dump + mem_dump
    task recv_dump_payload_parse;
        integer r, i;
        reg [7:0] b0,b1,b2,b3;
        begin
            for (r = 0; r < 32; r = r + 1) begin
                host_recv_byte(b0);
                host_recv_byte(b1);
                host_recv_byte(b2);
                host_recv_byte(b3);
                regs_dump[r] = {b3,b2,b1,b0};
            end
            for (i = 0; i < DM_DUMP_BYTES; i = i + 1) begin
                host_recv_byte(mem_dump[i]);
            end
        end
    endtask

    task program_word;
        input [31:0] addr;
        input [31:0] data;
        begin
            host_send_byte("P");
            host_send_u32_le(addr);
            host_send_u32_le(data);
            idle_ticks(50);
        end
    endtask

    task reset_fetch;
        begin
            host_send_byte("R");
            idle_ticks(200);
        end
    endtask

    task run_and_capture_dump;
        begin
            host_send_byte("G");
            recv_dump_header(type, flags, pc_le);
            expect8(type, 8'd2, "DUMP type RUN_END");
            if (flags[0] !== 1'b1) begin
                $display("[FAIL] halt_seen esperado 1 | flags=%02h", flags);
                $fatal;
            end
            if (flags[1] !== 1'b1) begin
                $display("[FAIL] pipe_empty esperado 1 | flags=%02h", flags);
                $fatal;
            end
            $display("[INFO] RUN_END flags=%02h pc=%08h (t=%0t)", flags, pc_le, $time);
            recv_dump_payload_parse();
        end
    endtask

    // ============================================================
    // NUEVO: limpiar IMEM con NOPs para evitar "basura" de tests previos
    // ============================================================
    task wipe_imem_nops;
        input [31:0] base;
        input integer n_words;
        integer k;
        begin
            for (k = 0; k < n_words; k = k + 1) begin
                program_word(base + (k*4), 32'h0000_0013); // NOP
            end
        end
    endtask

    // NUEVO: limpiar DMEM[0..63] (si te interesa determinismo)
    task wipe_dmem64;
        integer i;
        begin
            // x1 = 0
            program_word(32'h0000_0000, 32'h00000093); // addi x1,x0,0

            // loop i=0..63: sb x1, i(x0)
            // Como no tenemos loop real acá, lo hacemos desde el TB programando stores:
            // OJO: esto pisa IMEM, por eso se usa SOLO dentro de prepare_test, antes del programa real.
            for (i = 0; i < 64; i = i + 1) begin
                // sb x1, imm(x0)
                // encoding general sb: imm[11:5]|rs2|rs1|funct3|imm[4:0]|opcode
                // rs2=x1 (00001), rs1=x0 (00000), funct3=000, opcode=0100011 (0x23)
                // armamos inmediato i
                program_word(32'h0000_0004 + i*4,
                    { {20{1'b0}},
                      i[11:5], 5'd1, 5'd0, 3'b000, i[4:0], 7'b0100011 });
            end
            // ebreak al final
            program_word(32'h0000_0004 + 64*4, 32'h00100073);

            reset_fetch();
            run_and_capture_dump();
        end
    endtask

    // NUEVO: prepara cada test (limpia imem + opcional limpia dmem)
    task prepare_test;
        input integer clear_dmem;
        begin
            // 1) IMEM limpia: 0x00..0x7C (32 words) o más
            wipe_imem_nops(32'h0000_0000, 64); // 64 words = 256 bytes (0x00..0xFC)

            // 2) Opcional: DMEM limpia
            if (clear_dmem) begin
                wipe_dmem64();
            end
        end
    endtask

    // ============================================================
    // Programas de prueba
    // ============================================================

    task load_prog_alu_basic;
        begin
            program_word(32'h0000_0000, 32'h00500093); // addi x1,x0,5
            program_word(32'h0000_0004, 32'h00700113); // addi x2,x0,7
            program_word(32'h0000_0008, 32'h002081B3); // add  x3,x1,x2
            program_word(32'h0000_000C, 32'hFFE18213); // addi x4,x3,-2
            program_word(32'h0000_0010, 32'h00402023); // sw   x4,0(x0)
            program_word(32'h0000_0014, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_load_store;
        begin
            program_word(32'h0000_0000, 32'h07F00093); // addi x1,x0,0x7f
            program_word(32'h0000_0004, 32'h001000A3); // sb   x1,1(x0)
            program_word(32'h0000_0008, 32'h00104103); // lbu  x2,1(x0)
            program_word(32'h0000_000C, 32'hFFF00193); // addi x3,x0,-1
            program_word(32'h0000_0010, 32'h00300123); // sb   x3,2(x0)
            program_word(32'h0000_0014, 32'h00200203); // lb   x4,2(x0)
            program_word(32'h0000_0018, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_branch_jal_jalr;
        begin
            program_word(32'h0000_0000, 32'h00100093); // addi x1,x0,1
            program_word(32'h0000_0004, 32'h00100113); // addi x2,x0,1
            program_word(32'h0000_0008, 32'h00208463); // beq x1,x2,+8 -> 0x10
            program_word(32'h0000_000C, 32'h06300213); // addi x4,x0,99 (NO)
            program_word(32'h0000_0010, 32'h00000213); // addi x4,x0,0  (SI)
            program_word(32'h0000_0014, 32'h008002EF); // jal x5,+8 -> 0x1C
            program_word(32'h0000_0018, 32'h04D00213); // addi x4,x0,77 (NO)
            program_word(32'h0000_001C, 32'h02800393); // addi x7,x0,0x28
            program_word(32'h0000_0020, 32'h00038367); // jalr x6,x7,0 -> 0x28
            program_word(32'h0000_0024, 32'h00D00193); // addi x3,x0,13 (NO)
            program_word(32'h0000_0028, 32'h02A00193); // addi x3,x0,42 (SI)
            program_word(32'h0000_002C, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_hazard_load_use;
        begin
            program_word(32'h0000_0000, 32'h00700093); // addi x1,x0,7
            program_word(32'h0000_0004, 32'h00102023); // sw x1,0(x0)
            program_word(32'h0000_0008, 32'h00002103); // lw x2,0(x0)
            program_word(32'h0000_000C, 32'h002101B3); // add x3,x2,x2
            program_word(32'h0000_0010, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_lw_beq_hazard;
        begin
            program_word(32'h0000_0000, 32'h00100193); // addi x3,x0,1
            program_word(32'h0000_0004, 32'h00302023); // sw   x3,0(x0)
            program_word(32'h0000_0008, 32'h00002083); // lw x1,0(x0)
            program_word(32'h0000_000C, 32'h00008463); // beq x1,x0,+8
            program_word(32'h0000_0010, 32'h00900113); // addi x2,x0,9
            program_word(32'h0000_0014, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_jalr_align;
        begin
            program_word(32'h0000_0000, 32'h02900393); // addi x7,x0,0x29
            program_word(32'h0000_0004, 32'h00038367); // jalr x6,x7,0 -> 0x28
            program_word(32'h0000_0008, 32'h00D00193); // addi x3,x0,13 (NO)

            // padding / nops
            program_word(32'h0000_000C, 32'h00000013);
            program_word(32'h0000_0010, 32'h00000013);
            program_word(32'h0000_0014, 32'h00000013);
            program_word(32'h0000_0018, 32'h00000013);
            program_word(32'h0000_001C, 32'h00000013);
            program_word(32'h0000_0020, 32'h00000013);
            program_word(32'h0000_0024, 32'h00000013);

            program_word(32'h0000_0028, 32'h03700193); // addi x3,x0,55
            program_word(32'h0000_002C, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_beq_bne_both;
        begin
            program_word(32'h0000_0000, 32'h00500093); // addi x1,x0,5
            program_word(32'h0000_0004, 32'h00500113); // addi x2,x0,5
            program_word(32'h0000_0008, 32'h00208463); // beq x1,x2,+8
            program_word(32'h0000_000C, 32'h06300193); // addi x3,x0,99 (NO)
            program_word(32'h0000_0010, 32'h00100193); // addi x3,x0,1

            program_word(32'h0000_0014, 32'h00209463); // bne x1,x2,+8 (no toma)
            program_word(32'h0000_0018, 32'h00200213); // addi x4,x0,2

            program_word(32'h0000_001C, 32'h00600113); // addi x2,x0,6
            program_word(32'h0000_0020, 32'h00208463); // beq x1,x2,+8 (no toma)
            program_word(32'h0000_0024, 32'h00300293); // addi x5,x0,3

            program_word(32'h0000_0028, 32'h00209463); // bne x1,x2,+8 (toma)
            program_word(32'h0000_002C, 32'h05800313); // addi x6,x0,88 (NO)
            program_word(32'h0000_0030, 32'h00400313); // addi x6,x0,4 (SI)

            program_word(32'h0000_0034, 32'h00100073); // ebreak
        end
    endtask

    task load_prog_halfword_sh_lh_lhu;
        begin
            program_word(32'h0000_0000, 32'h000080B7); // lui  x1,0x8  -> 0x00008000
            program_word(32'h0000_0004, 32'h00108093); // addi x1,x1,1  -> 0x00008001
            program_word(32'h0000_0008, 32'h00101023); // sh x1,0(x0)
            program_word(32'h0000_000C, 32'h00001103); // lh  x2,0(x0)
            program_word(32'h0000_0010, 32'h00005183); // lhu x3,0(x0)
            program_word(32'h0000_0014, 32'h00100073); // ebreak
        end
    endtask

    // ============================================================
    // Main
    // ============================================================
    initial begin
        host_tx_start = 1'b0;
        host_tx_din   = 8'h00;

        reset = 1'b1;
        idle_ticks(50);
        reset = 1'b0;
        idle_ticks(200);

        // Smoke: dump manual
        host_send_byte("D");
        recv_dump_header(type, flags, pc_le);
        expect8(type, 8'd3, "DUMP type MANUAL");
        $display("[INFO] dump flags=%02h pc=%08h (t=%0t)", flags, pc_le, $time);
        recv_dump_payload_parse();

        expect_reg(0, 32'h0000_0000);

        // ========================================================
        // TEST 1
        // ========================================================
        $display("=== TEST 1: ALU BASIC ===");
        prepare_test(1); // limpia IMEM + DMEM
        load_prog_alu_basic();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(1, 32'd5);
        expect_reg(2, 32'd7);
        expect_reg(3, 32'd12);
        expect_reg(4, 32'd10);
        expect_mem8(0, 8'h0A);
        expect_mem8(1, 8'h00);
        expect_mem8(2, 8'h00);
        expect_mem8(3, 8'h00);

        // ========================================================
        // TEST 2
        // ========================================================
        $display("=== TEST 2: LOAD/STORE BYTE ===");
        prepare_test(1);
        load_prog_load_store();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(1, 32'h0000_007F);
        expect_reg(2, 32'h0000_007F);
        expect_reg(3, 32'hFFFF_FFFF);
        expect_reg(4, 32'hFFFF_FFFF);
        expect_mem8(1, 8'h7F);
        expect_mem8(2, 8'hFF);

        // ========================================================
        // TEST 3
        // ========================================================
        $display("=== TEST 3: BRANCH/JAL/JALR ===");
        prepare_test(1);
        load_prog_branch_jal_jalr();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(4, 32'd0);
        expect_reg(3, 32'd42);
        if (regs_dump[5] === 32'd0) begin $display("[FAIL] x5 (jal link) quedo 0"); $fatal; end
        if (regs_dump[6] === 32'd0) begin $display("[FAIL] x6 (jalr link) quedo 0"); $fatal; end
        if (regs_dump[5][1:0] !== 2'b00) begin $display("[FAIL] x5 no alineado"); $fatal; end
        if (regs_dump[6][1:0] !== 2'b00) begin $display("[FAIL] x6 no alineado"); $fatal; end

        // ========================================================
        // TEST 4
        // ========================================================
        $display("=== TEST 4: HAZARD LOAD-USE ===");
        prepare_test(1);
        load_prog_hazard_load_use();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(1, 32'd7);
        expect_reg(2, 32'd7);
        expect_reg(3, 32'd14);
        expect_mem8(0, 8'h07);
        expect_mem8(1, 8'h00);
        expect_mem8(2, 8'h00);
        expect_mem8(3, 8'h00);

        // ========================================================
        // TEST 5
        // ========================================================
        $display("=== TEST 5: LW->BEQ HAZARD ===");
        prepare_test(1);
        load_prog_lw_beq_hazard();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(1, 32'd1);
        expect_reg(2, 32'd9);

        // ========================================================
        // TEST 6
        // ========================================================
        $display("=== TEST 6: JALR ALIGN (target & ~1) ===");
        prepare_test(1);
        load_prog_jalr_align();
        reset_fetch();
        run_and_capture_dump();
        expect_reg(3, 32'd55);

        // ========================================================
        // TEST 7
        // ========================================================
        $display("=== TEST 7: BEQ/BNE BOTH PATHS ===");
        prepare_test(1);
        load_prog_beq_bne_both();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(3, 32'd1);
        expect_reg(4, 32'd2);
        expect_reg(5, 32'd3);
        expect_reg(6, 32'd4);

        // ========================================================
        // TEST 8
        // ========================================================
        $display("=== TEST 8: SH/LH/LHU SIGN+ZERO EXT ===");
        prepare_test(1);
        load_prog_halfword_sh_lh_lhu();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(1, 32'h0000_8001);
        expect_reg(2, 32'hFFFF_8001);
        expect_reg(3, 32'h0000_8001);
        expect_mem8(0, 8'h01);
        expect_mem8(1, 8'h80);

        $display("========================================");
        $display("FIN: tb_top_debug_system EXTENDED OK");
        $display("========================================");
        $finish;
    end

endmodule

`default_nettype wire
