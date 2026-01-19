`timescale 1ns/1ps

module tb_hazard_detection_unit;

    reg idex_mem_read;
    reg [4:0] idex_rd, ifid_rs1, ifid_rs2;

    wire pc_en, ifid_write_en, idex_flush;

    hazard_detection_unit dut (
        .idex_mem_read(idex_mem_read),
        .idex_rd(idex_rd),
        .ifid_rs1(ifid_rs1),
        .ifid_rs2(ifid_rs2),
        .pc_en(pc_en),
        .ifid_write_en(ifid_write_en),
        .idex_flush(idex_flush)
    );

    task settle; begin #2; end endtask

    task check1(input got, input exp, input [127:0] name);
    begin
        if (got !== exp) $display("ERROR %0s: got=%0d exp=%0d", name, got, exp);
        else             $display("OK    %0s", name);
    end
    endtask

    initial begin
        // init
        idex_mem_read = 0;
        idex_rd = 0;
        ifid_rs1 = 0;
        ifid_rs2 = 0;

        // Caso 1: no load -> no stall
        idex_mem_read = 0;
        idex_rd = 5'd4;
        ifid_rs1 = 5'd4;
        ifid_rs2 = 5'd1;
        settle();
        check1(pc_en, 1, "No stall: pc_en=1");
        check1(ifid_write_en, 1, "No stall: ifid_write_en=1");
        check1(idex_flush, 0, "No stall: idex_flush=0");

        // Caso 2: load-use en rs1 -> stall
        idex_mem_read = 1;
        idex_rd = 5'd4;
        ifid_rs1 = 5'd4;
        ifid_rs2 = 5'd2;
        settle();
        check1(pc_en, 0, "Stall: pc_en=0");
        check1(ifid_write_en, 0, "Stall: ifid_write_en=0");
        check1(idex_flush, 1, "Stall: idex_flush=1");

        // Caso 3: load-use en rs2 -> stall
        idex_mem_read = 1;
        idex_rd = 5'd7;
        ifid_rs1 = 5'd1;
        ifid_rs2 = 5'd7;
        settle();
        check1(pc_en, 0, "Stall(rs2): pc_en=0");
        check1(idex_flush, 1, "Stall(rs2): idex_flush=1");

        // Caso 4: rd=0 no debe stallar
        idex_mem_read = 1;
        idex_rd = 5'd0;
        ifid_rs1 = 5'd0;
        ifid_rs2 = 5'd0;
        settle();
        check1(pc_en, 1, "rd=0 ignored: pc_en=1");
        check1(idex_flush, 0, "rd=0 ignored: idex_flush=0");

        $display("Fin TB hazard_detection_unit.");
        $stop;
    end

endmodule
