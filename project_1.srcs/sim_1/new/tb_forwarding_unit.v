`timescale 1ns/1ps

module tb_forwarding_unit;

    reg        exmem_reg_write;
    reg [4:0]  exmem_rd;

    reg        memwb_reg_write;
    reg [4:0]  memwb_rd;

    reg [4:0]  idex_rs1, idex_rs2;

    wire [1:0] forward_a, forward_b;

    forwarding_unit dut (
        .exmem_reg_write(exmem_reg_write),
        .exmem_rd(exmem_rd),
        .memwb_reg_write(memwb_reg_write),
        .memwb_rd(memwb_rd),
        .idex_rs1(idex_rs1),
        .idex_rs2(idex_rs2),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    task settle; begin #2; end endtask

    task check2(input [1:0] got, input [1:0] exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%b exp=%b", name, got, exp);
        else             $display("OK    %0s", name);
    end
    endtask

    initial begin
        // init
        exmem_reg_write = 0; exmem_rd = 0;
        memwb_reg_write = 0; memwb_rd = 0;
        idex_rs1 = 0; idex_rs2 = 0;

        // Caso 1: sin dependencias
        idex_rs1 = 5'd1; idex_rs2 = 5'd2;
        settle();
        check2(forward_a, 2'b00, "No hazard: ForwardA=00");
        check2(forward_b, 2'b00, "No hazard: ForwardB=00");

        // Caso 2: match en EX/MEM para rs1
        exmem_reg_write = 1; exmem_rd = 5'd1;
        settle();
        check2(forward_a, 2'b10, "EX/MEM hazard rs1: ForwardA=10");
        check2(forward_b, 2'b00, "No hazard rs2: ForwardB=00");

        // Caso 3: match en MEM/WB para rs2
        exmem_reg_write = 0; exmem_rd = 5'd0;
        memwb_reg_write = 1; memwb_rd = 5'd2;
        settle();
        check2(forward_a, 2'b00, "No hazard rs1: ForwardA=00");
        check2(forward_b, 2'b01, "MEM/WB hazard rs2: ForwardB=01");

        // Caso 4: ambos match para rs1 -> prioridad EX/MEM
        exmem_reg_write = 1; exmem_rd = 5'd1;
        memwb_reg_write = 1; memwb_rd = 5'd1;
        settle();
        check2(forward_a, 2'b10, "Priority EX/MEM over MEM/WB for rs1");

        // Caso 5: rd==0 nunca forwardea
        exmem_rd = 5'd0; // x0
        settle();
        check2(forward_a, 2'b01, "EX/MEM rd=0 ignored, MEM/WB used if match"); // memwb_rd==1, idex_rs1==1

        // Ajuste para probar rd==0 en MEM/WB también
        memwb_rd = 5'd0;
        settle();
        check2(forward_a, 2'b00, "MEM/WB rd=0 ignored => no forwarding");

        $display("Fin TB forwarding_unit.");
        $stop;
    end

endmodule
