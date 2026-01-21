`timescale 1ns/1ps

module tb_dmem_rv32;

    localparam BYTES = 256;

    reg clk;
    reg mem_read, mem_write;
    reg [2:0] funct3;
    reg [31:0] addr;
    reg [31:0] write_data;
    wire [31:0] read_data;

    dmem_rv32 #(
        .BYTES(BYTES),
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

    task do_store;
        input [2:0]  f3;
        input [31:0] a;
        input [31:0] wd;
        begin
            @(negedge clk);
            funct3    = f3;
            addr      = a;
            write_data= wd;
            mem_write = 1'b1;
            mem_read  = 1'b0;
            @(posedge clk);
            #1;
            mem_write = 1'b0;
        end
    endtask

    task do_load_expect;
        input [2:0]  f3;
        input [31:0] a;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            funct3   = f3;
            addr     = a;
            mem_read = 1'b1;
            mem_write= 1'b0;
            #1;
            expect32(read_data, exp, msg);
            mem_read = 1'b0;
        end
    endtask

    initial begin
        mem_read = 0;
        mem_write = 0;
        funct3 = 3'b010;
        addr = 0;
        write_data = 0;

        // 1) SW + LW (little-endian)
        do_store(3'b010, 32'h0000_0010, 32'hA1B2_C3D4); // SW
        do_load_expect(3'b010, 32'h0000_0010, 32'hA1B2_C3D4, "LW @0x10 == A1B2C3D4");

        // Verificar bytes individuales en offsets (D4 C3 B2 A1)
        do_load_expect(3'b100, 32'h0000_0010, 32'h0000_00D4, "LBU @0x10 == D4");
        do_load_expect(3'b100, 32'h0000_0011, 32'h0000_00C3, "LBU @0x11 == C3");
        do_load_expect(3'b100, 32'h0000_0012, 32'h0000_00B2, "LBU @0x12 == B2");
        do_load_expect(3'b100, 32'h0000_0013, 32'h0000_00A1, "LBU @0x13 == A1");

        // 2) LB vs LBU (sign extend)
        do_store(3'b000, 32'h0000_0020, 32'h0000_0080); // SB 0x80
        do_load_expect(3'b000, 32'h0000_0020, 32'hFFFF_FF80, "LB  @0x20 sign-extends 0x80");
        do_load_expect(3'b100, 32'h0000_0020, 32'h0000_0080, "LBU @0x20 zero-extends 0x80");

        // 3) SH + LH/LHU offset 0
        do_store(3'b001, 32'h0000_0030, 32'h0000_8001); // SH -> bytes: 01 80
        do_load_expect(3'b001, 32'h0000_0030, 32'hFFFF_8001, "LH  @0x30 sign-extends 0x8001");
        do_load_expect(3'b101, 32'h0000_0030, 32'h0000_8001, "LHU @0x30 zero-extends 0x8001");

        // 4) SH offset 2 dentro de la misma word alineada
        do_store(3'b001, 32'h0000_0042, 32'h0000_7FEE); // SH @0x42 -> EE 7F
        do_load_expect(3'b101, 32'h0000_0042, 32'h0000_7FEE, "LHU @0x42 == 0x7FEE");
        do_load_expect(3'b001, 32'h0000_0042, 32'h0000_7FEE, "LH  @0x42 == 0x7FEE");

        // 5) Lectura deshabilitada => 0
        funct3   = 3'b010;
        addr     = 32'h0000_0010;
        mem_read = 1'b0;
        #1;
        expect32(read_data, 32'h0000_0000, "mem_read=0 => read_data=0");

        $display("========================================");
        $display("FIN: tb_dmem_rv32 OK");
        $display("========================================");
        $finish;
    end

endmodule
