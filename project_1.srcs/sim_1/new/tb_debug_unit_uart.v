`timescale 1ns/1ps
`default_nettype none

module tb_debug_unit_uart;

  // ---------------- clock/reset ----------------
  reg clk, reset;
  initial clk = 0;
  always #5 clk = ~clk; // 100MHz

  // ---------------- UART RX emulado ----------------
  reg        rx_done_tick;
  reg [7:0]  rx_dout;

  // ---------------- UART TX emulado ----------------
  wire       tx_start;
  wire [7:0] tx_din;
  reg        tx_done_tick;

  // ---------------- CPU->DEBUG (mock) -------------
  reg  [31:0]        dbg_pc;
  reg                dbg_pipe_empty;
  reg                dbg_halt_seen;
  reg  [23*32-1:0]    dbg_pipe_flat;

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

  // ---------------- stream ports (nuevo DUT) -------
  wire [4:0]  rf_dbg_addr;
  reg  [31:0] rf_dbg_data;

  wire [11:0] dmem_dbg_addr;
  reg  [7:0]  dmem_dbg_data;

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
    .dbg_pipe_flat(dbg_pipe_flat),

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
  // Mock REGFILE + DMEM
  // ============================================================
  reg [31:0] rf_mem [0:31];
  reg [7:0]  dm_mem [0:4095]; // suficiente para addr[11:0]

  integer i;
  initial begin
    for (i = 0; i < 32; i = i + 1)
      rf_mem[i] = i * 32'h11111111;

    for (i = 0; i < 4096; i = i + 1)
      dm_mem[i] = i[7:0];
  end

  // Comb: responder a la dirección que pide el DUT
  always @(*) begin
    rf_dbg_data   = rf_mem[rf_dbg_addr];
    dmem_dbg_data = dm_mem[dmem_dbg_addr];
  end

  // ============================================================
  // Dump capture (NUEVO tamaño)
  // Header(4) + PC(4) + PIPE(92) + REGS(128) + MEM(64) = 292
  // ============================================================
  localparam integer PIPE_WORDS      = 23;
  localparam integer DUMP_HDR_BYTES  = 4;
  localparam integer DUMP_PC_BYTES   = 4;
  localparam integer DUMP_PIPE_BYTES = PIPE_WORDS*4; // 92
  localparam integer DUMP_REG_BYTES  = 32*4;         // 128
  localparam integer DUMP_MEM_BYTES  = 64;           // DM_DUMP_BYTES default

  localparam integer OFF_PC   = 4;
  localparam integer OFF_PIPE = 8;
  localparam integer OFF_REG  = 8 + DUMP_PIPE_BYTES;               // 100
  localparam integer OFF_MEM  = 8 + DUMP_PIPE_BYTES + DUMP_REG_BYTES; // 228

  localparam integer DUMP_TOTAL = DUMP_HDR_BYTES + DUMP_PC_BYTES + DUMP_PIPE_BYTES + DUMP_REG_BYTES + DUMP_MEM_BYTES; // 292

  reg [7:0] dump_bytes [0:DUMP_TOTAL-1];
  integer dump_count;

  always @(posedge clk) begin
    if (reset) begin
      dump_count <= 0;
    end else if (tx_start) begin
      if (dump_count < DUMP_TOTAL)
        dump_bytes[dump_count] <= tx_din;
      dump_count <= dump_count + 1;
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

  // Emulación TX: cada tx_start termina 1 ciclo después
  always @(posedge clk) begin
    if (reset) tx_done_tick <= 1'b0;
    else       tx_done_tick <= tx_start;
  end

  // Detector robusto del pulso imem_dbg_we
  reg saw_imem_we;
  always @(posedge clk) begin
    if (reset) saw_imem_we <= 1'b0;
    else if (imem_dbg_we)  saw_imem_we <= 1'b1;
  end

  // Helper para detectar pulsos (evita carreras de delta-ciclos)
  task expect_pulse_1cycle(input reg sig, input [127:0] name);
    integer k;
    reg seen;
  begin
    seen = 0;
    for (k = 0; k < 5; k = k + 1) begin
      @(posedge clk);
      if (sig) seen = 1;
    end
    if (!seen) $display("ERROR %0s: no pulso", name);
    else       $display("OK    %0s: pulso", name);
  end
  endtask

  // ============================================================
  // Inicialización del "mock CPU"
  // ============================================================
  initial begin
    rx_done_tick   = 0;
    rx_dout        = 8'h00;

    dbg_pc         = 32'h0000_00C8;
    dbg_pipe_empty = 1'b0;
    dbg_halt_seen  = 1'b0;

    // PIPE: 23 words con patrón (word i = 0xA0000000 + i)
    for (i = 0; i < PIPE_WORDS; i = i + 1)
      dbg_pipe_flat[i*32 +: 32] = 32'hA000_0000 + i;
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

    // esperar pulso
    begin : WAIT_WE
      integer tmo;
      tmo = 0;
      while (!saw_imem_we && tmo < 200) begin
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
    
    // mirar inmediatamente el ciclo siguiente
    @(posedge clk);
    if (dbg_flush_pipe) $display("OK    dbg_flush_pipe pulso");
    else                $display("ERROR dbg_flush_pipe no pulso");
    
    if (dbg_load_pc)    $display("OK    dbg_load_pc pulso");
    else                $display("ERROR dbg_load_pc no pulso");
    
    // ---------------- TEST 3: G ----------------
    $display("---- TEST 3: Comando G (RUN->HALT->DRAIN->DUMP) ----");
    dump_count = 0;

    send_byte("G");

    // dbg_run debe ponerse en 1 al entrar a ST_RUN
    repeat (2) @(posedge clk);
    if (dbg_run !== 1'b1) $display("ERROR G: dbg_run no se activo");
    else                  $display("OK    G: dbg_run activo");

    // simular HALT
    repeat (8) @(posedge clk);
    dbg_halt_seen = 1'b1;
    $display("Mock: dbg_halt_seen=1");

    // ahora debería entrar en DRAIN
    repeat (3) @(posedge clk);
    if (dbg_drain !== 1'b1) $display("ERROR: no entro en dbg_drain");
    else                    $display("OK    entro en dbg_drain");

    // simular pipeline empty
    repeat (6) @(posedge clk);
    dbg_pipe_empty = 1'b1;
    $display("Mock: dbg_pipe_empty=1");

    // esperar dump completo
    wait (dump_count >= DUMP_TOTAL);
    $display("OK    dump emitido: %0d bytes (esperado %0d)", dump_count, DUMP_TOTAL);

    // ---------------- CHECK DUMP ----------------
    $display("---- CHECK DUMP HEADER ----");
    check8(dump_bytes[0], 8'hD0, "dump[0] magic");
    check8(dump_bytes[1], 8'd2,  "dump[1] dump_type RUN_END");
    check8(dump_bytes[2], 8'h03, "dump[2] flags (pipe_empty+halt_seen)");
    check8(dump_bytes[3], 8'h00, "dump[3] reserved");

    $display("---- CHECK PC ----");
    check32(u32_from_dump(OFF_PC), dbg_pc, "PC word");

    $display("---- CHECK sample PIPE word 7 ----");
    // word7 está en OFF_PIPE + 7*4
    check32(u32_from_dump(OFF_PIPE + 7*4), 32'hA000_0007, "pipe[7] word");

    $display("---- CHECK sample REG x3 ----");
    // x3 en OFF_REG + 3*4
    check32(u32_from_dump(OFF_REG + 3*4), rf_mem[3], "x3 word");

    $display("---- CHECK sample DMEM[10] ----");
    check8(dump_bytes[OFF_MEM + 10], dm_mem[10], "dmem[10]");

    $display("Fin TB debug_unit_uart OK.");
    $stop;
  end

endmodule

`default_nettype wire
