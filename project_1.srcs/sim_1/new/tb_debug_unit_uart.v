`timescale 1ns/1ps

module tb_debug_unit_uart;

  // ---------------- clock/reset ----------------
  reg clk, reset;
  initial clk = 0;
  always #5 clk = ~clk;

  // ---------------- UART RX emulado ----------------
  reg        rx_done_tick;
  reg [7:0]  rx_dout;

  // ---------------- UART TX emulado ----------------
  wire       tx_start;
  wire [7:0] tx_din;
  reg        tx_done_tick;

  // ---------------- CPU->DEBUG (mock) -------------
  reg  [31:0] dbg_pc;
  reg         dbg_pipe_empty;
  reg         dbg_halt_seen;
  reg  [32*32-1:0] dbg_regs_flat;
  reg  [64*8-1:0]  dbg_dmem_flat;

  // ---------------- DEBUG->CPU (salidas DUT) ------
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

  // ---------------- DUT ---------------------------
  debug_unit_uart dut (
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
    .dbg_regs_flat(dbg_regs_flat),
    .dbg_dmem_flat(dbg_dmem_flat),

    .dbg_freeze(dbg_freeze),
    .dbg_run(dbg_run),
    .dbg_step(dbg_step),
    .dbg_drain(dbg_drain),

    .dbg_flush_pipe(dbg_flush_pipe),
    .dbg_load_pc(dbg_load_pc),
    .dbg_pc_value(dbg_pc_value),

    .imem_dbg_we(imem_dbg_we),
    .imem_dbg_addr(imem_dbg_addr),
    .imem_dbg_wdata(imem_dbg_wdata)
  );

  // ============================================================
  // Dump capture
  // ============================================================
  localparam integer DUMP_TOTAL = 200; // 4 + 4 + 128 + 64
  reg [7:0] dump_bytes [0:DUMP_TOTAL-1];
  integer dump_count;

  always @(posedge clk) begin
    if (reset) begin
      dump_count <= 0;
    end else begin
      if (tx_start) begin
        if (dump_count < DUMP_TOTAL)
          dump_bytes[dump_count] <= tx_din;
        dump_count <= dump_count + 1;
      end
    end
  end

  // ============================================================
  // Helpers
  // ============================================================
  task send_byte(input [7:0] b);
  begin
    @(negedge clk);
    rx_dout      = b;
    rx_done_tick = 1'b1;
    @(negedge clk);
    rx_done_tick = 1'b0;
  end
  endtask

  task send_u32_le(input [31:0] w);
  begin
    send_byte(w[7:0]);
    send_byte(w[15:8]);
    send_byte(w[23:16]);
    send_byte(w[31:24]);
  end
  endtask

  task check32(input [31:0] got, input [31:0] exp, input [127:0] name);
  begin
    if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
    else             $display("OK    %0s", name);
  end
  endtask

  task check8(input [7:0] got, input [7:0] exp, input [127:0] name);
  begin
    if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
    else             $display("OK    %0s", name);
  end
  endtask

  function [31:0] u32_from_dump;
    input integer base;
    begin
      u32_from_dump = { dump_bytes[base+3], dump_bytes[base+2], dump_bytes[base+1], dump_bytes[base+0] };
    end
  endfunction

  function [31:0] reg_flat_word;
    input integer r;
    begin
      reg_flat_word = dbg_regs_flat[r*32 +: 32];
    end
  endfunction

  function [7:0] mem_flat_byte;
    input integer i;
    begin
      mem_flat_byte = dbg_dmem_flat[i*8 +: 8];
    end
  endfunction

  // ============================================================
  // Emulación TX: cada tx_start termina 1 ciclo después
  // ============================================================
  always @(posedge clk) begin
    if (reset) tx_done_tick <= 1'b0;
    else       tx_done_tick <= tx_start;
  end

  // ============================================================
  // Detector robusto del pulso imem_dbg_we
  // ============================================================
  reg saw_imem_we;
  always @(posedge clk) begin
    if (reset) saw_imem_we <= 1'b0;
    else if (imem_dbg_we)  saw_imem_we <= 1'b1;
  end

  // ============================================================
  // Inicialización del "mock CPU"
  // ============================================================
  integer r;
  integer m;
  initial begin
    rx_done_tick   = 0;
    rx_dout        = 8'h00;

    dbg_pc         = 32'h0000_00C8;
    dbg_pipe_empty = 0;
    dbg_halt_seen  = 0;

    dbg_regs_flat  = { (32*32){1'b0} };
    dbg_dmem_flat  = { (64*8){1'b0} };

    for (r = 0; r < 32; r = r + 1)
      dbg_regs_flat[r*32 +: 32] = (r * 32'h11111111);

    for (m = 0; m < 64; m = m + 1)
      dbg_dmem_flat[m*8 +: 8] = m[7:0];
  end

  // ============================================================
  // TEST SEQUENCE
  // ============================================================
  initial begin
    reset = 1;
    repeat (5) @(negedge clk);
    reset = 0;

    // ---------------- TEST 1: P ----------------
    $display("---- TEST 1: Comando P (programar IMEM) ----");
    saw_imem_we = 0;

    send_byte("P");
    send_u32_le(32'h0000_0010);   // addr
    send_u32_le(32'hDEAD_BEEF);   // data

    // esperar hasta ver pulso o timeout
    begin : WAIT_WE
      integer tmo;
      tmo = 0;
      while (!saw_imem_we && tmo < 100) begin
        @(posedge clk);
        tmo = tmo + 1;
      end
      if (!saw_imem_we) $display("ERROR imem_dbg_we no pulso (timeout)");
      else              $display("OK    imem_dbg_we pulso");
    end

    check32(imem_dbg_addr,  32'h0000_0010, "imem_dbg_addr");
    check32(imem_dbg_wdata, 32'hDEAD_BEEF, "imem_dbg_wdata");

    // ---------------- TEST 2: R ----------------
    $display("---- TEST 2: Comando R (soft reset fetch) ----");
    send_byte("R");

    @(posedge clk);
    if (dbg_flush_pipe !== 1'b1 || dbg_load_pc !== 1'b1)
      $display("ERROR R: dbg_flush_pipe/dbg_load_pc no pulsaron");
    else
      $display("OK    R: pulso flush+load_pc");
    check32(dbg_pc_value, 32'h0000_0000, "dbg_pc_value");

    // ---------------- TEST 3: G ----------------
    $display("---- TEST 3: Comando G (RUN->HALT->DRAIN->DUMP) ----");
    dump_count = 0;

    send_byte("G");

    repeat (2) @(posedge clk);
    if (dbg_run !== 1'b1) $display("ERROR G: dbg_run no se activo");
    else                  $display("OK    G: dbg_run activo");

    // simular HALT
    repeat (8) @(posedge clk);
    dbg_halt_seen = 1'b1;
    $display("Mock: dbg_halt_seen=1");

    repeat (2) @(posedge clk);
    if (dbg_drain !== 1'b1) $display("ERROR: no entro en dbg_drain");
    else                    $display("OK    entro en dbg_drain");

    // simular pipeline empty
    repeat (6) @(posedge clk);
    dbg_pipe_empty = 1'b1;
    $display("Mock: dbg_pipe_empty=1");

    // esperar dump completo
    wait (dump_count >= DUMP_TOTAL);
    $display("OK    dump emitido: %0d bytes", dump_count);

    // ---------------- CHECK DUMP ----------------
    $display("---- CHECK DUMP HEADER ----");
    check8(dump_bytes[0], 8'hD0, "dump[0] magic");
    check8(dump_bytes[1], 8'd2,  "dump[1] dump_type RUN_END");
    check8(dump_bytes[2], 8'h03, "dump[2] flags (pipe_empty+halt_seen)");
    check8(dump_bytes[3], 8'h00, "dump[3] reserved");

    $display("---- CHECK PC ----");
    check32(u32_from_dump(4), dbg_pc, "PC word");

    $display("---- CHECK sample REG x3 ----");
    check32(u32_from_dump(8 + 3*4), reg_flat_word(3), "x3 word");

    $display("---- CHECK sample DMEM[10] ----");
    check8(dump_bytes[136 + 10], mem_flat_byte(10), "dmem[10]");

    $display("Fin TB debug_unit_uart OK.");
    $stop;
  end

endmodule
