`timescale 1ns/1ps
`default_nettype none

module tb_top;

    reg clk, reset;

    reg        dbg_freeze;
    reg        dbg_flush_pipe;
    reg        dbg_load_pc;
    reg [31:0] dbg_pc_value;

    reg        imem_dbg_we;
    reg [31:0] imem_dbg_addr;
    reg [31:0] imem_dbg_wdata;

    reg        dbg_run;
    reg        dbg_step;
    reg        dbg_drain;

    wire       dbg_pipe_empty;
    wire       dbg_halt_seen;
    wire [31:0]        dbg_pc;
    wire [23*32-1:0]   dbg_pipe_flat;

    // NUEVOS puertos debug "stream"
    reg  [4:0]  rf_dbg_addr;
    wire [31:0] rf_dbg_data;
    reg  [11:0] dmem_dbg_addr;
    wire [7:0]  dmem_dbg_data;

    cpu_top #(
        .IMEM_FILE(""),
        .DMEM_FILE("")
    ) dut (
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
        .dbg_pipe_flat(dbg_pipe_flat),

        .rf_dbg_addr(rf_dbg_addr),
        .rf_dbg_data(rf_dbg_data),
        .dmem_dbg_addr(dmem_dbg_addr),
        .dmem_dbg_data(dmem_dbg_data)
    );

    // clock 100MHz sim (10ns)
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------
    // Encoders RV32I (igual que antes)
    // ----------------------------
    function automatic [31:0] ENC_R;
        input [6:0] funct7;
        input [4:0] rs2, rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            ENC_R = {funct7, rs2, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] ENC_I;
        input integer imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        reg [11:0] im12;
        begin
            im12 = imm[11:0];
            ENC_I = {im12, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] ENC_S;
        input integer imm;
        input [4:0] rs2, rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        reg [11:0] im12;
        begin
            im12 = imm[11:0];
            ENC_S = {im12[11:5], rs2, rs1, funct3, im12[4:0], opcode};
        end
    endfunction

    function automatic [31:0] ENC_B;
        input integer imm;
        input [4:0] rs2, rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        reg [12:0] im13;
        begin
            im13 = imm[12:0];
            ENC_B = {im13[12], im13[10:5], rs2, rs1, funct3, im13[4:1], im13[11], opcode};
        end
    endfunction

    function automatic [31:0] ENC_U;
        input [19:0] imm20;
        input [4:0]  rd;
        input [6:0]  opcode;
        begin
            ENC_U = {imm20, rd, opcode};
        end
    endfunction

    function automatic [31:0] ENC_J;
        input integer imm;
        input [4:0] rd;
        input [6:0] opcode;
        reg [20:0] im21;
        begin
            im21 = imm[20:0];
            ENC_J = {im21[20], im21[10:1], im21[11], im21[19:12], rd, opcode};
        end
    endfunction

    function automatic [31:0] ENC_SHIFTI;
        input [6:0] funct7;
        input [4:0] shamt;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            ENC_SHIFTI = {funct7, shamt, rs1, funct3, rd, opcode};
        end
    endfunction

    localparam [6:0] OP      = 7'b0110011;
    localparam [6:0] OP_IMM  = 7'b0010011;
    localparam [6:0] LOAD    = 7'b0000011;
    localparam [6:0] STORE   = 7'b0100011;
    localparam [6:0] BRANCH  = 7'b1100011;
    localparam [6:0] JAL     = 7'b1101111;
    localparam [6:0] JALR    = 7'b1100111;
    localparam [6:0] LUI     = 7'b0110111;

    // ----------------------------
    // Expect
    // ----------------------------
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

    // ----------------------------
    // IMEM write (igual)
    // ----------------------------
    task imem_write_word;
        input [31:0] byte_addr;
        input [31:0] wdata;
        begin
            @(negedge clk);
            imem_dbg_addr  = byte_addr;
            imem_dbg_wdata = wdata;
            imem_dbg_we    = 1'b1;
            @(posedge clk);
            @(negedge clk);
            imem_dbg_we    = 1'b0;
        end
    endtask

    task force_pc0;
        begin
            @(negedge clk);
            dbg_pc_value = 32'h0000_0000;
            dbg_load_pc  = 1'b1;
            @(posedge clk);
            @(negedge clk);
            dbg_load_pc  = 1'b0;
        end
    endtask

    // ----------------------------
    // NUEVO: snapshot regs + dmem
    // ----------------------------
    reg [31:0] regs_snap [0:31];
    reg [7:0]  dmem_snap [0:63];

    task snap_regs;
        integer r;
        begin
            for (r = 0; r < 32; r = r + 1) begin
                rf_dbg_addr = r[4:0];
                #1; // deja propagar combinacional
                regs_snap[r] = rf_dbg_data;
            end
        end
    endtask

    task snap_dmem64;
        integer b;
        begin
            for (b = 0; b < 64; b = b + 1) begin
                dmem_dbg_addr = b[11:0];
                #1;
                dmem_snap[b] = dmem_dbg_data;
            end
        end
    endtask

    function automatic [31:0] X;
        input integer r;
        begin
            X = regs_snap[r];
        end
    endfunction

    function automatic [31:0] DMEM_WORD64;
        input integer byte_addr;
        begin
            DMEM_WORD64 = { dmem_snap[byte_addr+3],
                            dmem_snap[byte_addr+2],
                            dmem_snap[byte_addr+1],
                            dmem_snap[byte_addr+0] };
        end
    endfunction

    integer cycles;

    initial begin
        reset = 1;

        dbg_freeze     = 0;
        dbg_flush_pipe = 0;
        dbg_load_pc    = 0;
        dbg_pc_value   = 0;

        imem_dbg_we    = 0;
        imem_dbg_addr  = 0;
        imem_dbg_wdata = 0;

        dbg_run   = 0;
        dbg_step  = 0;
        dbg_drain = 0;

        rf_dbg_addr   = 0;
        dmem_dbg_addr = 0;

        @(posedge clk);
        @(posedge clk);
        reset = 0;

        // ----------------------------
        // Programa (PC base = 0)
        // ----------------------------
        imem_write_word(32'h0000_0000, ENC_I(32, 5'd0, 3'b000, 5'd10, OP_IMM));         // addi x10,x0,32

        imem_write_word(32'h0000_0004, ENC_U(20'hA1B2C, 5'd11, LUI));                  // lui x11,0xA1B2C
        imem_write_word(32'h0000_0008, ENC_I(12'h3D4, 5'd11, 3'b000, 5'd11, OP_IMM));  // addi x11,x11,0x3D4

        imem_write_word(32'h0000_000C, ENC_S(0, 5'd11, 5'd10, 3'b010, STORE));         // sw x11,0(x10)

        imem_write_word(32'h0000_0010, ENC_I(0, 5'd10, 3'b010, 5'd12, LOAD));          // lw x12,0(x10)
        imem_write_word(32'h0000_0014, ENC_I(0, 5'd10, 3'b010, 5'd13, LOAD));          // lw x13,0(x10)
        imem_write_word(32'h0000_0018, ENC_S(4, 5'd13, 5'd10, 3'b010, STORE));         // sw x13,4(x10)

        imem_write_word(32'h0000_001C, ENC_I(0, 5'd10, 3'b000, 5'd14, LOAD));          // lb x14,0(x10)
        imem_write_word(32'h0000_0020, ENC_I(0, 5'd10, 3'b100, 5'd15, LOAD));          // lbu x15,0(x10)
        imem_write_word(32'h0000_0024, ENC_I(0, 5'd10, 3'b001, 5'd16, LOAD));          // lh x16,0(x10)
        imem_write_word(32'h0000_0028, ENC_I(0, 5'd10, 3'b101, 5'd17, LOAD));          // lhu x17,0(x10)

        imem_write_word(32'h0000_002C, ENC_R(7'b0000000, 5'd13, 5'd12, 3'b000, 5'd18, OP)); // add
        imem_write_word(32'h0000_0030, ENC_R(7'b0100000, 5'd13, 5'd12, 3'b000, 5'd19, OP)); // sub

        imem_write_word(32'h0000_0034, ENC_I(12'h0FF, 5'd11, 3'b111, 5'd20, OP_IMM)); // andi

        imem_write_word(32'h0000_0038, ENC_I(1, 5'd0, 3'b000, 5'd21, OP_IMM));         // addi x21,1

        imem_write_word(32'h0000_003C, ENC_B(8, 5'd0, 5'd19, 3'b000, BRANCH));         // beq x19,x0,+8
        imem_write_word(32'h0000_0040, ENC_I(1, 5'd21, 3'b000, 5'd21, OP_IMM));        // skipped

        imem_write_word(32'h0000_0044, ENC_B(8, 5'd0, 5'd21, 3'b001, BRANCH));         // bne x21,x0,+8
        imem_write_word(32'h0000_0048, ENC_I(2, 5'd21, 3'b000, 5'd21, OP_IMM));        // skipped

        imem_write_word(32'h0000_004C, ENC_J(8, 5'd22, JAL));                          // jal x22,+8
        imem_write_word(32'h0000_0050, ENC_I(123, 5'd0, 3'b000, 5'd23, OP_IMM));       // skipped

        imem_write_word(32'h0000_0054, ENC_I(7, 5'd0, 3'b000, 5'd23, OP_IMM));         // addi x23,7

        imem_write_word(32'h0000_0058, ENC_SHIFTI(7'b0000000, 5'd2, 5'd23, 3'b001, 5'd26, OP_IMM)); // slli
        imem_write_word(32'h0000_005C, ENC_SHIFTI(7'b0000000, 5'd1, 5'd26, 3'b101, 5'd27, OP_IMM)); // srli

        imem_write_word(32'h0000_0060, ENC_I(108, 5'd0, 3'b000, 5'd5, OP_IMM));        // addi x5,108
        imem_write_word(32'h0000_0064, ENC_I(0, 5'd5, 3'b000, 5'd6, JALR));            // jalr x6,x5,0
        imem_write_word(32'h0000_0068, ENC_I(0, 5'd0, 3'b000, 5'd24, OP_IMM));         // skipped
        imem_write_word(32'h0000_006C, ENC_I(9, 5'd0, 3'b000, 5'd24, OP_IMM));         // addi x24,9

        imem_write_word(32'h0000_0070, 32'h0010_0073);                                 // ebreak

        force_pc0();

        // run
        dbg_run = 1'b1;

        cycles = 0;
        while (!dbg_halt_seen && cycles < 500) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!dbg_halt_seen) begin
            $display("[FAIL] No se detecto EBREAK en %0d ciclos", cycles);
            $fatal;
        end

        // deja que el pipeline termine de asentar WB/MEM si hace falta
        repeat (8) @(posedge clk);

        // snapshot con los puertos nuevos
        snap_regs();
        snap_dmem64();

        // ----------------------------
        // Reg checks
        // ----------------------------
        expect32(X(10), 32'd32,         "x10 base addr");
        expect32(X(11), 32'hA1B2_C3D4,  "x11 pattern");
        expect32(X(12), 32'hA1B2_C3D4,  "x12 lw");
        expect32(X(13), 32'hA1B2_C3D4,  "x13 lw");
        expect32(X(14), 32'hFFFF_FFD4,  "x14 lb sign");
        expect32(X(15), 32'h0000_00D4,  "x15 lbu");
        expect32(X(16), 32'hFFFF_C3D4,  "x16 lh sign");
        expect32(X(17), 32'h0000_C3D4,  "x17 lhu");
        expect32(X(18), 32'h4365_87A8,  "x18 add");
        expect32(X(19), 32'h0000_0000,  "x19 sub");
        expect32(X(20), 32'h0000_00D4,  "x20 andi");
        expect32(X(21), 32'h0000_0001,  "x21 branch path");
        expect32(X(22), 32'h0000_0050,  "x22 jal link");
        expect32(X(23), 32'h0000_0007,  "x23 after jal");
        expect32(X(26), 32'h0000_001C,  "x26 slli");
        expect32(X(27), 32'h0000_000E,  "x27 srli");
        expect32(X(5),  32'h0000_006C,  "x5 jalr target");
        expect32(X(6),  32'h0000_0068,  "x6 jalr link");
        expect32(X(24), 32'h0000_0009,  "x24 after jalr");

        // ----------------------------
        // DMEM checks (solo bytes 0..63)
        // Nota: en tu programa, x10=32 => primer SW en 0x20
        // ----------------------------
        expect32(DMEM_WORD64(32), 32'hA1B2_C3D4, "mem[0x20] word");
        expect32(DMEM_WORD64(36), 32'hA1B2_C3D4, "mem[0x24] word (lw->sw)");

        $display("========================================");
        $display("FIN: tb_cpu_top (nuevo top) OK");
        $display("========================================");
        $finish;
    end

endmodule

`default_nettype wire
