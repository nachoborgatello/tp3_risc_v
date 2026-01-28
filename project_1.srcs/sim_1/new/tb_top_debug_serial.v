`timescale 1ns/1ps
`default_nettype none

module tb_top_debug_system;

    // TB clock: 100 MHz
    localparam integer CLK_TB_HZ     = 100_000_000;

    localparam integer BAUD          = 115200;
    localparam integer DM_DUMP_BYTES = 64;
    localparam integer PIPE_WORDS    = 23;

    reg clk, reset;

    wire dut_uart_rx;
    wire dut_uart_tx;
    wire s_tick_out;

    top_debug_system #(
        .CLK_IN_HZ(CLK_TB_HZ),
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

    // ============================================================
    // Host UART con tick propio (NO usa s_tick_out del DUT)
    // ============================================================
    localparam integer TICK_HZ_HOST = BAUD * 16;
    localparam integer M_TICK_HOST  = (CLK_TB_HZ / TICK_HZ_HOST);

    function integer clog2;
        input integer v;
        integer i;
        begin
            i = 0;
            while ((1<<i) < v) i = i + 1;
            clog2 = i;
        end
    endfunction

    localparam integer N_TICK_HOST = (M_TICK_HOST <= 2) ? 1 : clog2(M_TICK_HOST);

    wire s_tick_host;
    wire [N_TICK_HOST-1:0] q_tick_host;

    mod_m_counter #(
        .N(N_TICK_HOST),
        .M(M_TICK_HOST)
    ) u_host_baud_tick (
        .clk(clk),
        .reset(reset),
        .max_tick(s_tick_host),
        .q(q_tick_host)
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
        .s_tick(s_tick_host),
        .din(host_tx_din),
        .tx_done_tick(host_tx_done_tick),
        .tx(host_tx_line)
    );

    uart_rx #(.DBIT(8), .SB_TICK(16)) u_host_rx (
        .clk(clk),
        .reset(reset),
        .rx(dut_uart_tx),
        .s_tick(s_tick_host),
        .rx_done_tick(host_rx_done_tick),
        .dout(host_rx_dout)
    );

    assign dut_uart_rx = host_tx_line;

    // Clock 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------
    // Scoreboard buffers
    // ---------------------------
    reg [31:0] pipe_dump [0:PIPE_WORDS-1];
    reg [31:0] regs_dump [0:31];
    reg [7:0]  mem_dump  [0:DM_DUMP_BYTES-1];

    reg [31:0] pipe_prev [0:PIPE_WORDS-1];

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
            idle_ticks(10);
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
                if (guard > 10_000_000) begin
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
        output [7:0]  type_o;
        output [7:0]  flags_o;
        output [31:0] pc_le_o;
        reg [7:0] b;
        begin
            host_recv_byte(b); expect8(b, 8'hD0, "DUMP[0] magic");
            host_recv_byte(type_o);
            host_recv_byte(flags_o);
            host_recv_byte(b); expect8(b, 8'h00, "DUMP[3] pad");

            host_recv_byte(b); pc_le_o[7:0]   = b;
            host_recv_byte(b); pc_le_o[15:8]  = b;
            host_recv_byte(b); pc_le_o[23:16] = b;
            host_recv_byte(b); pc_le_o[31:24] = b;
        end
    endtask

    task recv_dump_payload_parse;
        integer w, r, i;
        reg [7:0] b0,b1,b2,b3;
        begin
            // PIPE (23 words)
            for (w = 0; w < PIPE_WORDS; w = w + 1) begin
                host_recv_byte(b0);
                host_recv_byte(b1);
                host_recv_byte(b2);
                host_recv_byte(b3);
                pipe_dump[w] = {b3,b2,b1,b0};
            end

            // REGS (32 words)
            for (r = 0; r < 32; r = r + 1) begin
                host_recv_byte(b0);
                host_recv_byte(b1);
                host_recv_byte(b2);
                host_recv_byte(b3);
                regs_dump[r] = {b3,b2,b1,b0};
            end

            // DMEM bytes
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
            idle_ticks(20);
        end
    endtask

    task reset_fetch;
        begin
            host_send_byte("R");
            idle_ticks(400);
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

    task step_and_capture_dump;
        begin
            host_send_byte("S");
            recv_dump_header(type, flags, pc_le);
            expect8(type, 8'd1, "DUMP type STEP");
            $display("[INFO] STEP flags=%02h pc=%08h (t=%0t)", flags, pc_le, $time);
            recv_dump_payload_parse();
        end
    endtask

    task expect_pipe_not_all_zero;
        integer k;
        reg any_nonzero;
        begin
            any_nonzero = 1'b0;
            for (k = 0; k < PIPE_WORDS; k = k + 1)
                if (pipe_dump[k] !== 32'h0000_0000) any_nonzero = 1'b1;

            if (!any_nonzero) begin
                $display("[FAIL] STEP: pipe_dump todo cero (t=%0t)", $time);
                $fatal;
            end else begin
                $display("[ OK ] STEP: pipe_dump tiene actividad (t=%0t)", $time);
            end
        end
    endtask

    task save_pipe_snapshot;
        integer k;
        begin
            for (k = 0; k < PIPE_WORDS; k = k + 1)
                pipe_prev[k] = pipe_dump[k];
        end
    endtask

    task expect_pipe_changed_since_last;
        integer k;
        reg changed;
        begin
            changed = 1'b0;
            for (k = 0; k < PIPE_WORDS; k = k + 1)
                if (pipe_dump[k] !== pipe_prev[k]) changed = 1'b1;

            if (!changed) begin
                $display("[FAIL] STEP: pipe_dump NO cambió (t=%0t)", $time);
                $fatal;
            end else begin
                $display("[ OK ] STEP: pipe_dump cambió (t=%0t)", $time);
            end
        end
    endtask

    // Limpieza IMEM (NOP)
    task wipe_imem_nops;
        input [31:0] base;
        input integer n_words;
        integer k;
        begin
            for (k = 0; k < n_words; k = k + 1)
                program_word(base + (k*4), 32'h0000_0013);
        end
    endtask

    // Limpieza DMEM[0..63] con un mini-programa
    task wipe_dmem64;
        integer i;
        begin
            program_word(32'h0000_0000, 32'h00000093); // addi x1,x0,0
            for (i = 0; i < 64; i = i + 1) begin
                program_word(32'h0000_0004 + i*4,
                    { 20'b0, i[11:5], 5'd1, 5'd0, 3'b000, i[4:0], 7'b0100011 }); // sb
            end
            program_word(32'h0000_0004 + 64*4, 32'h00100073);
            reset_fetch();
            run_and_capture_dump();
        end
    endtask

    task prepare_test;
        input integer clear_dmem;
        begin
            wipe_imem_nops(32'h0000_0000, 128);
            if (clear_dmem) wipe_dmem64();
        end
    endtask

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

    initial begin
        host_tx_start = 1'b0;
        host_tx_din   = 8'h00;

        reset = 1'b1;
        idle_ticks(50);
        reset = 1'b0;

        // esperar un toque
        idle_ticks(2000);

        // Smoke: MANUAL dump
        host_send_byte("D");
        recv_dump_header(type, flags, pc_le);
        expect8(type, 8'd3, "DUMP type MANUAL");
        $display("[INFO] MANUAL flags=%02h pc=%08h (t=%0t)", flags, pc_le, $time);
        recv_dump_payload_parse();
        expect_reg(0, 32'h0000_0000);

        // TEST
        $display("=== TEST: ALU BASIC ===");
        prepare_test(1);
        load_prog_alu_basic();
        reset_fetch();
        run_and_capture_dump();

        expect_reg(1, 32'd5);
        expect_reg(2, 32'd7);
        expect_reg(3, 32'd12);
        expect_reg(4, 32'd10);

        // STEP
        $display("=== TEST STEP ===");
        prepare_test(0);
        load_prog_alu_basic();
        reset_fetch();

        step_and_capture_dump();
        expect_pipe_not_all_zero();
        save_pipe_snapshot();

        step_and_capture_dump();
        expect_pipe_changed_since_last();

        $display("========================================");
        $display("FIN: tb_top_debug_system OK");
        $display("========================================");
        $finish;
    end

endmodule

`default_nettype wire
