`timescale 1ns/1ps

module tb_dmem_rv32;

    reg clk;
    reg mem_read, mem_write;
    reg [2:0] funct3;
    reg [31:0] addr, write_data;
    wire [31:0] read_data;

    dmem_rv32 #(
        .BYTES(256),
        .MEM_FILE("")
    ) dut (
        .clk(clk),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .funct3(funct3),
        .addr(addr),
        .write_data(write_data),
        .read_data(read_data)
    );

    // Clock 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // settle para combinacional
    task settle; begin #2; end endtask

    task check32(input [31:0] got, input [31:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
        else            $display("OK    %0s", name);
    end
    endtask

    // Write helpers (se escriben en posedge)
    task do_store(input [2:0] f3, input [31:0] a, input [31:0] wd);
    begin
        @(negedge clk);
        mem_read  = 0;
        mem_write = 1;
        funct3    = f3;
        addr      = a;
        write_data= wd;
        @(posedge clk);
        @(negedge clk);
        mem_write = 0;
    end
    endtask

    // Read helpers (combinacional)
    task do_load_check(input [2:0] f3, input [31:0] a, input [31:0] exp, input [127:0] name);
    begin
        mem_write = 0;
        mem_read  = 1;
        funct3    = f3;
        addr      = a;
        settle();
        check32(read_data, exp, name);
        mem_read  = 0;
    end
    endtask

    initial begin
        // init
        mem_read = 0;
        mem_write = 0;
        funct3 = 3'b000;
        addr = 0;
        write_data = 0;

        // -------------------------
        // 1) SB y luego LB/LBU
        // guardo 0x80 en addr 0x10
        do_store(3'b000, 32'h0000_0010, 32'h0000_0080); // SB (write_data[7:0]=0x80)

        // LB debe sign-extend: 0xFFFFFF80
        do_load_check(3'b000, 32'h0000_0010, 32'hFFFF_FF80, "LB sign-extend 0x80");

        // LBU debe zero-extend: 0x00000080
        do_load_check(3'b100, 32'h0000_0010, 32'h0000_0080, "LBU zero-extend 0x80");

        // -------------------------
        // 2) SH y luego LH/LHU
        // guardo 0x8001 en addr 0x20 (alineada a 2)
        do_store(3'b001, 32'h0000_0020, 32'h0000_8001); // SH

        // LH sign-extend: 0xFFFF8001
        do_load_check(3'b001, 32'h0000_0020, 32'hFFFF_8001, "LH sign-extend 0x8001");

        // LHU zero-extend: 0x00008001
        do_load_check(3'b101, 32'h0000_0020, 32'h0000_8001, "LHU zero-extend 0x8001");

        // -------------------------
        // 3) SW y luego LW
        // guardo palabra completa en addr 0x40 (alineada a 4)
        do_store(3'b010, 32'h0000_0040, 32'hDEAD_BEEF); // SW
        do_load_check(3'b010, 32'h0000_0040, 32'hDEAD_BEEF, "LW after SW");

        // -------------------------
        // 4) Prueba de offsets dentro de la palabra (LB en +1, +2, +3)
        // escribo 0x11223344 en 0x50 y leo bytes
        do_store(3'b010, 32'h0000_0050, 32'h1122_3344); // SW
        // little-endian: mem[0x50]=44, [0x51]=33, [0x52]=22, [0x53]=11
        do_load_check(3'b100, 32'h0000_0050, 32'h0000_0044, "LBU byte0");
        do_load_check(3'b100, 32'h0000_0051, 32'h0000_0033, "LBU byte1");
        do_load_check(3'b100, 32'h0000_0052, 32'h0000_0022, "LBU byte2");
        do_load_check(3'b100, 32'h0000_0053, 32'h0000_0011, "LBU byte3");

        $display("Fin TB dmem_rv32.");
        $stop;
    end

endmodule
