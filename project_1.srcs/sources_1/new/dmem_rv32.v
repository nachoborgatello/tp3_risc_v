`timescale 1ns/1ps

module dmem_rv32 #(
    parameter integer BYTES    = 4096,
    parameter         MEM_FILE = ""
)(
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output wire [31:0] read_data
);

    // Memoria de bytes
    reg [7:0] mem [0:BYTES-1];
    integer i;

    // Para indexar BYTES bytes
    localparam integer AW = (BYTES <= 2) ? 1 : $clog2(BYTES);

    // Índices recortados (evita out-of-range si addr tiene bits altos)
    wire [AW-1:0] a = addr[AW-1:0];

    // Dirección alineada a word (addr & ~3), también recortada
    wire [31:0] base32 = {addr[31:2], 2'b00};
    wire [AW-1:0] b    = base32[AW-1:0];

    // Init
    initial begin
        for (i = 0; i < BYTES; i = i + 1)
            mem[i] = 8'h00;

        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    // ---------------------------
    // Lectura: armar word alineada (little-endian)
    // ---------------------------
    wire [31:0] word_aligned = {
        mem[b + {{(AW-2){1'b0}}, 2'd3}],
        mem[b + {{(AW-2){1'b0}}, 2'd2}],
        mem[b + {{(AW-2){1'b0}}, 2'd1}],
        mem[b + {{(AW-2){1'b0}}, 2'd0}]
    };

    wire [1:0] byte_off = addr[1:0];

    wire [7:0] sel_byte =
        (byte_off == 2'd0) ? word_aligned[7:0]   :
        (byte_off == 2'd1) ? word_aligned[15:8]  :
        (byte_off == 2'd2) ? word_aligned[23:16] :
                             word_aligned[31:24];

    wire [15:0] sel_half =
        (addr[1] == 1'b0) ? word_aligned[15:0] :
                            word_aligned[31:16];

    // Read combinacional
    reg [31:0] rdata;
    always @(*) begin
        rdata = 32'd0;

        if (mem_read) begin
            case (funct3)
                3'b000: rdata = {{24{sel_byte[7]}}, sel_byte};  // LB
                3'b001: rdata = {{16{sel_half[15]}}, sel_half}; // LH
                3'b010: rdata = word_aligned;                   // LW
                3'b100: rdata = {24'd0, sel_byte};              // LBU
                3'b101: rdata = {16'd0, sel_half};              // LHU
                default: rdata = 32'd0;
            endcase
        end
    end

    assign read_data = rdata;

    // ---------------------------
    // Escritura sincrónica (byte-addressed)
    // ---------------------------
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB
                    mem[a] <= write_data[7:0];
                end

                3'b001: begin // SH
                    mem[a]       <= write_data[7:0];
                    mem[a + 1]   <= write_data[15:8];
                end

                3'b010: begin // SW
                    mem[a]       <= write_data[7:0];
                    mem[a + 1]   <= write_data[15:8];
                    mem[a + 2]   <= write_data[23:16];
                    mem[a + 3]   <= write_data[31:24];
                end

                default: begin end
            endcase
        end
    end

endmodule
