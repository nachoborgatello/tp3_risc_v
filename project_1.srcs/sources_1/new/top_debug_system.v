`timescale 1ns/1ps
`default_nettype none

module top_debug_system #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200,

    // CPU params
    parameter IMEM_FILE = "",
    parameter DMEM_FILE = ""
)(
    input  wire clk,
    input  wire reset,

    input  wire uart_rx,
    output wire uart_tx,
    output wire s_tick_out
);

    // Debug read ports (stream)
    wire [4:0]  rf_dbg_addr;
    wire [31:0] rf_dbg_data;
    wire [11:0] dmem_dbg_addr;
    wire [7:0]  dmem_dbg_data;

    // ============================================================
    // 1) Baud tick para oversampling 16x
    // ============================================================
    localparam integer TICK_HZ = BAUD * 16;
    localparam integer M_TICK  = (CLK_HZ / TICK_HZ);

    function integer clog2;
        input integer v;
        integer i;
        begin
            i = 0;
            while ((1<<i) < v) i = i + 1;
            clog2 = i;
        end
    endfunction

    localparam integer N_TICK = (M_TICK <= 2) ? 1 : clog2(M_TICK);

    wire s_tick;
    wire [N_TICK-1:0] q_tick;

    mod_m_counter #(
        .N(N_TICK),
        .M(M_TICK)
    ) u_baud_tick (
        .clk(clk),
        .reset(reset),
        .max_tick(s_tick),
        .q(q_tick)
    );

    // ============================================================
    // 2) UART RX/TX
    // ============================================================
    wire       rx_done_tick;
    wire [7:0] rx_dout;

    uart_rx #(
        .DBIT(8),
        .SB_TICK(16)
    ) u_uart_rx (
        .clk(clk),
        .reset(reset),
        .rx(uart_rx),
        .s_tick(s_tick),
        .rx_done_tick(rx_done_tick),
        .dout(rx_dout)
    );

    wire       tx_done_tick;
    wire       tx_start;
    wire [7:0] tx_din;

    uart_tx #(
        .DBIT(8),
        .SB_TICK(16)
    ) u_uart_tx (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .s_tick(s_tick),
        .din(tx_din),
        .tx_done_tick(tx_done_tick),
        .tx(uart_tx)
    );

    // ============================================================
    // 3) Señales DEBUG <-> CPU
    // ============================================================
    wire        dbg_freeze;
    wire        dbg_run;
    wire        dbg_step;
    wire        dbg_drain;

    wire        dbg_flush_pipe;
    wire        dbg_load_pc;
    wire [31:0] dbg_pc_value;

    wire        imem_dbg_we;
    wire [31:0] imem_dbg_addr;
    wire [31:0] imem_dbg_wdata;

    wire [31:0] dbg_pc;
    wire        dbg_pipe_empty;
    wire        dbg_halt_seen;

    // ============================================================
    // 4) Debug Unit (stream por puertos)
    // ============================================================
    debug_unit_uart u_dbg (
        .clk(clk),
        .reset(reset),

        .rx_done_tick(rx_done_tick),
        .rx_dout(rx_dout),

        .tx_start(tx_start),
        .tx_din(tx_din),
        .tx_done_tick(tx_done_tick),

        .dbg_pc(dbg_pc),
        .dbg_pipe_empty(dbg_pipe_empty),
        .dbg_halt_seen(dbg_halt_seen),

        .dbg_freeze(dbg_freeze),
        .dbg_run(dbg_run),
        .dbg_step(dbg_step),
        .dbg_drain(dbg_drain),

        .dbg_flush_pipe(dbg_flush_pipe),
        .dbg_load_pc(dbg_load_pc),
        .dbg_pc_value(dbg_pc_value),

        .imem_dbg_we(imem_dbg_we),
        .imem_dbg_addr(imem_dbg_addr),
        .imem_dbg_wdata(imem_dbg_wdata),

        .rf_dbg_addr(rf_dbg_addr),
        .rf_dbg_data(rf_dbg_data),
        .dmem_dbg_addr(dmem_dbg_addr),
        .dmem_dbg_data(dmem_dbg_data)
    );

    // ============================================================
    // 5) CPU TOP
    // ============================================================
    cpu_top #(
      .IMEM_FILE(IMEM_FILE),
      .DMEM_FILE(DMEM_FILE)
    ) u_cpu (
      .clk(clk),
      .reset(reset),

      .dbg_freeze(dbg_freeze),
      .dbg_flush_pipe(dbg_flush_pipe),
      .dbg_load_pc(dbg_load_pc),
      .dbg_pc_value(dbg_pc_value),

      .imem_dbg_we(imem_dbg_we),
      .imem_dbg_addr(imem_dbg_addr),
      .imem_dbg_wdata(imem_dbg_wdata),

      .dbg_run(dbg_run),
      .dbg_step(dbg_step),
      .dbg_drain(dbg_drain),

      .dbg_pipe_empty(dbg_pipe_empty),
      .dbg_halt_seen(dbg_halt_seen),

      .dbg_pc(dbg_pc),

      .rf_dbg_addr(rf_dbg_addr),
      .rf_dbg_data(rf_dbg_data),
      .dmem_dbg_addr(dmem_dbg_addr),
      .dmem_dbg_data(dmem_dbg_data)
    );

    assign s_tick_out = s_tick;

endmodule

`default_nettype wire
