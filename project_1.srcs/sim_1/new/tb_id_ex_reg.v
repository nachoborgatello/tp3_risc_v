`timescale 1ns/1ps

module tb_id_ex_reg;

    reg clk, reset;
    reg write_en, flush;

    // Inputs DATA
    reg [31:0] pc_in, rs1_data_in, rs2_data_in, imm_in;
    reg [4:0]  rs1_in, rs2_in, rd_in;
    reg [2:0]  funct3_in;
    reg [6:0]  funct7_in;

    // Inputs CONTROL
    reg        reg_write_in, mem_to_reg_in;
    reg        mem_read_in, mem_write_in, branch_in;
    reg        alu_src_in;
    reg [1:0]  alu_op_in;
    reg        jump_in, jalr_in;

    // Outputs DATA
    wire [31:0] pc_out, rs1_data_out, rs2_data_out, imm_out;
    wire [4:0]  rs1_out, rs2_out, rd_out;
    wire [2:0]  funct3_out;
    wire [6:0]  funct7_out;

    // Outputs CONTROL
    wire reg_write_out, mem_to_reg_out;
    wire mem_read_out, mem_write_out, branch_out;
    wire alu_src_out;
    wire [1:0] alu_op_out;
    wire jump_out, jalr_out;

    id_ex_reg dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .flush(flush),

        .pc_in(pc_in),
        .rs1_data_in(rs1_data_in),
        .rs2_data_in(rs2_data_in),
        .imm_in(imm_in),
        .rs1_in(rs1_in),
        .rs2_in(rs2_in),
        .rd_in(rd_in),
        .funct3_in(funct3_in),
        .funct7_in(funct7_in),

        .reg_write_in(reg_write_in),
        .mem_to_reg_in(mem_to_reg_in),

        .mem_read_in(mem_read_in),
        .mem_write_in(mem_write_in),
        .branch_in(branch_in),

        .alu_src_in(alu_src_in),
        .alu_op_in(alu_op_in),

        .jump_in(jump_in),
        .jalr_in(jalr_in),

        .pc_out(pc_out),
        .rs1_data_out(rs1_data_out),
        .rs2_data_out(rs2_data_out),
        .imm_out(imm_out),
        .rs1_out(rs1_out),
        .rs2_out(rs2_out),
        .rd_out(rd_out),
        .funct3_out(funct3_out),
        .funct7_out(funct7_out),

        .reg_write_out(reg_write_out),
        .mem_to_reg_out(mem_to_reg_out),

        .mem_read_out(mem_read_out),
        .mem_write_out(mem_write_out),
        .branch_out(branch_out),

        .alu_src_out(alu_src_out),
        .alu_op_out(alu_op_out),

        .jump_out(jump_out),
        .jalr_out(jalr_out)
    );

    // Clock 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    task check(input cond, input [127:0] msg);
    begin
        if (!cond) $display("ERROR: %0s", msg);
        else       $display("OK   : %0s", msg);
    end
    endtask

    initial begin
        // init
        reset = 1;
        write_en = 1;
        flush = 0;

        // valores de prueba
        pc_in = 32'h0000_0010;
        rs1_data_in = 32'd100;
        rs2_data_in = 32'd200;
        imm_in = 32'd12;

        rs1_in = 5'd1;
        rs2_in = 5'd2;
        rd_in  = 5'd3;
        funct3_in = 3'b010;
        funct7_in = 7'b0000000;

        reg_write_in = 1;
        mem_to_reg_in= 0;

        mem_read_in  = 0;
        mem_write_in = 1;
        branch_in    = 0;

        alu_src_in   = 1;
        alu_op_in    = 2'b00;

        jump_in = 0;
        jalr_in = 0;

        // soltar reset
        #20;
        reset = 0;

        // 1) Cargar normal en el primer flanco
        @(posedge clk);
        #1;
        check(pc_out == 32'h0000_0010, "Load: pc_out");
        check(rs1_data_out == 32'd100, "Load: rs1_data_out");
        check(rs2_data_out == 32'd200, "Load: rs2_data_out");
        check(imm_out == 32'd12, "Load: imm_out");
        check(rd_out == 5'd3, "Load: rd_out");
        check(mem_write_out == 1'b1, "Load: mem_write_out");
        check(alu_src_out == 1'b1, "Load: alu_src_out");

        // 2) Stall: cambiar inputs pero no debe cambiar outputs
        write_en = 0;
        pc_in = 32'h0000_0020;
        rs1_data_in = 32'd111;
        mem_write_in = 0;
        @(posedge clk);
        #1;
        check(pc_out == 32'h0000_0010, "Stall: pc_out no cambia");
        check(rs1_data_out == 32'd100, "Stall: rs1_data_out no cambia");
        check(mem_write_out == 1'b1, "Stall: mem_write_out no cambia");

        // 3) Volver a habilitar y cargar nuevos valores
        write_en = 1;
        @(posedge clk);
        #1;
        check(pc_out == 32'h0000_0020, "Reload: pc_out cambia");
        check(rs1_data_out == 32'd111, "Reload: rs1_data_out cambia");
        check(mem_write_out == 1'b0, "Reload: mem_write_out cambia");

        // 4) Flush: debe insertar burbuja (todo 0)
        flush = 1;
        @(posedge clk);
        #1;
        flush = 0;

        check(pc_out == 32'b0, "Flush: pc_out=0");
        check(reg_write_out == 1'b0, "Flush: reg_write_out=0");
        check(mem_write_out == 1'b0, "Flush: mem_write_out=0");
        check(alu_op_out == 2'b00, "Flush: alu_op_out=00");

        $display("Fin TB ID/EX.");
        $stop;
    end

endmodule
