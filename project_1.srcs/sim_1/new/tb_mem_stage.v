`timescale 1ns / 1ps

module tb_mem_stage;

    reg clk;

    // Inputs
    reg        mem_read, mem_write;
    reg [2:0]  funct3;
    reg [31:0] alu_result_in;
    reg [31:0] write_data;

    // Outputs
    wire [31:0] mem_read_data;
    wire [31:0] alu_result_out;

    // DUT
    mem_stage #(
        .DM_BYTES(256),
        .DM_FILE("")
    ) dut (
        .clk(clk),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .funct3(funct3),
        .alu_result_in(alu_result_in),
        .write_data(write_data),
        .mem_read_data(mem_read_data),
        .alu_result_out(alu_result_out)
    );

    // Clock 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // settle para lectura combinacional
    task settle; begin #2; end endtask

    task check32(input [31:0] got, input [31:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%h exp=%h", name, got, exp);
        else            $display("OK    %0s", name);
    end
    endtask

    // Helpers de store (escritura en posedge)
    task do_store(input [2:0] f3, input [31:0] addr, input [31:0] wd, input [127:0] name);
    begin
        @(negedge clk);
        funct3 = f3;
        alu_result_in = addr;
        write_data = wd;
        mem_write = 1;
        mem_read  = 0;

        // passthrough siempre debe reflejar la entrada
        settle();
        check32(alu_result_out, addr, {name, " passthrough"});

        @(posedge clk); // escritura efectiva
        @(negedge clk);
        mem_write = 0;
    end
    endtask

    // Helpers de load (lectura combinacional)
    task do_load_check(input [2:0] f3, input [31:0] addr, input [31:0] exp, input [127:0] name);
    begin
        funct3 = f3;
        alu_result_in = addr;
        mem_write = 0;
        mem_read  = 1;

        // passthrough
        settle();
        check32(alu_result_out, addr, {name, " passthrough"});

        // dato leido
        check32(mem_read_data, exp, name);

        mem_read = 0;
    end
    endtask

    initial begin
        // init
        mem_read = 0;
        mem_write = 0;
        funct3 = 3'b000;
        alu_result_in = 0;
        write_data = 0;

        settle();

        // ------------------------------------------------------------
        // 1) SW/LW
        do_store(3'b010, 32'h0000_0040, 32'hDEAD_BEEF, "SW @0x40");
        do_load_check(3'b010, 32'h0000_0040, 32'hDEAD_BEEF, "LW @0x40");

        // ------------------------------------------------------------
        // 2) SB + LB/LBU (probar sign/zero extend)
        // guardo 0x80 en 0x10
        do_store(3'b000, 32'h0000_0010, 32'h0000_0080, "SB @0x10 (0x80)");
        do_load_check(3'b000, 32'h0000_0010, 32'hFFFF_FF80, "LB @0x10 (sign)");
        do_load_check(3'b100, 32'h0000_0010, 32'h0000_0080, "LBU @0x10 (zero)");

        // ------------------------------------------------------------
        // 3) SH + LH/LHU (probar sign/zero extend)
        // guardo 0x8001 en 0x20
        do_store(3'b001, 32'h0000_0020, 32'h0000_8001, "SH @0x20 (0x8001)");
        do_load_check(3'b001, 32'h0000_0020, 32'hFFFF_8001, "LH @0x20 (sign)");
        do_load_check(3'b101, 32'h0000_0020, 32'h0000_8001, "LHU @0x20 (zero)");

        // ------------------------------------------------------------
        // 4) Accesos con offsets dentro de una palabra (byte1/2/3)
        // SW 0x11223344 en 0x50, little endian:
        // mem[0x50]=44, [0x51]=33, [0x52]=22, [0x53]=11
        do_store(3'b010, 32'h0000_0050, 32'h1122_3344, "SW @0x50 (0x11223344)");
        do_load_check(3'b100, 32'h0000_0050, 32'h0000_0044, "LBU @0x50 byte0");
        do_load_check(3'b100, 32'h0000_0051, 32'h0000_0033, "LBU @0x51 byte1");
        do_load_check(3'b100, 32'h0000_0052, 32'h0000_0022, "LBU @0x52 byte2");
        do_load_check(3'b100, 32'h0000_0053, 32'h0000_0011, "LBU @0x53 byte3");

        $display("Fin TB mem_stage.");
        $stop;
    end

endmodule
