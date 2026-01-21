`timescale 1ns/1ps

module tb_mem_stage;

    localparam DM_BYTES = 256;

    reg clk;

    reg mem_read, mem_write;
    reg [2:0] funct3;
    reg [31:0] alu_result_in;
    reg [31:0] write_data;

    wire [31:0] mem_read_data;
    wire [31:0] alu_result_out;

    mem_stage #(
        .DM_BYTES(DM_BYTES),
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
            funct3        = f3;
            alu_result_in = a;
            write_data    = wd;
            mem_write     = 1'b1;
            mem_read      = 1'b0;
            @(posedge clk);
            #1;
            mem_write     = 1'b0;
        end
    endtask

    task do_load_expect;
        input [2:0]  f3;
        input [31:0] a;
        input [31:0] exp;
        input [256*8-1:0] msg;
        begin
            funct3        = f3;
            alu_result_in = a;
            mem_read      = 1'b1;
            mem_write     = 1'b0;
            #1;
            expect32(mem_read_data, exp, msg);
            mem_read      = 1'b0;
        end
    endtask

    initial begin
        mem_read = 0;
        mem_write = 0;
        funct3 = 3'b010;
        alu_result_in = 0;
        write_data = 0;

        // SW + LW
        do_store(3'b010, 32'h0000_0010, 32'hA1B2_C3D4);
        #1;
        expect32(alu_result_out, 32'h0000_0010, "passthrough alu_result_out (store)");

        do_load_expect(3'b010, 32'h0000_0010, 32'hA1B2_C3D4, "LW @0x10");
        #1;
        expect32(alu_result_out, 32'h0000_0010, "passthrough alu_result_out (load)");

        // SB + LB/LBU
        do_store(3'b000, 32'h0000_0020, 32'h0000_0080);
        do_load_expect(3'b000, 32'h0000_0020, 32'hFFFF_FF80, "LB  @0x20");
        do_load_expect(3'b100, 32'h0000_0020, 32'h0000_0080, "LBU @0x20");

        $display("========================================");
        $display("FIN: tb_mem_stage OK");
        $display("========================================");
        $finish;
    end

endmodule
