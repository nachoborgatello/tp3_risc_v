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
    output wire [31:0] read_data,

    input  wire [11:0] dbg_byte_addr,
    output wire [7:0]  dbg_byte_data
);

    // ---- Organización en palabras ----
    localparam integer WORDS = BYTES / 4;
    localparam integer WA    = (WORDS <= 2) ? 1 : $clog2(WORDS);

    wire [WA-1:0] waddr = addr[WA+1:2];   // índice de palabra
    wire [1:0]    boff  = addr[1:0];      // offset de byte dentro de la palabra

    // Debug byte addressing
    wire [WA-1:0] dbg_waddr = dbg_byte_addr[WA+1:2];
    wire [1:0]    dbg_boff  = dbg_byte_addr[1:0];

    // ---- 4 bancos de 8 bits (byte lanes) ----
    // Sugerencia a Vivado: implementar como distributed RAM
    (* ram_style = "distributed" *) reg [7:0] mem0 [0:WORDS-1]; // byte 0 (LSB)
    (* ram_style = "distributed" *) reg [7:0] mem1 [0:WORDS-1]; // byte 1
    (* ram_style = "distributed" *) reg [7:0] mem2 [0:WORDS-1]; // byte 2
    (* ram_style = "distributed" *) reg [7:0] mem3 [0:WORDS-1]; // byte 3 (MSB)

    integer i;

    // Init (simulación; en FPGA real podés dejarlo o inicializar por archivo)
    initial begin
        for (i = 0; i < WORDS; i = i + 1) begin
            mem0[i] = 8'h00;
            mem1[i] = 8'h00;
            mem2[i] = 8'h00;
            mem3[i] = 8'h00;
        end
        // Si tenés MEM_FILE en formato "word por línea" (32b), podés cargarlo fácil:
        // $readmemh(MEM_FILE, tmp_words) y repartir. Para no tocarte el flujo, lo dejo vacío acá.
    end

    // ---- Lectura combinacional (igual a tu comportamiento actual) ----
    wire [31:0] word_aligned = { mem3[waddr], mem2[waddr], mem1[waddr], mem0[waddr] };

    wire [7:0] sel_byte =
        (boff == 2'd0) ? word_aligned[7:0]   :
        (boff == 2'd1) ? word_aligned[15:8]  :
        (boff == 2'd2) ? word_aligned[23:16] :
                         word_aligned[31:24];

    wire [15:0] sel_half =
        (addr[1] == 1'b0) ? word_aligned[15:0] :
                            word_aligned[31:16];

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

    // ---- Escritura sincrónica (sin multiwrite al mismo array) ----
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB
                    case (boff)
                        2'd0: mem0[waddr] <= write_data[7:0];
                        2'd1: mem1[waddr] <= write_data[7:0];
                        2'd2: mem2[waddr] <= write_data[7:0];
                        2'd3: mem3[waddr] <= write_data[7:0];
                    endcase
                end

                3'b001: begin // SH (asumimos alineado a 2 bytes)
                    if (addr[1] == 1'b0) begin
                        mem0[waddr] <= write_data[7:0];
                        mem1[waddr] <= write_data[15:8];
                    end else begin
                        mem2[waddr] <= write_data[7:0];
                        mem3[waddr] <= write_data[15:8];
                    end
                end

                3'b010: begin // SW
                    mem0[waddr] <= write_data[7:0];
                    mem1[waddr] <= write_data[15:8];
                    mem2[waddr] <= write_data[23:16];
                    mem3[waddr] <= write_data[31:24];
                end

                default: begin end
            endcase
        end
    end

    // ---- Debug byte combinacional (no toca CPU) ----
    reg [7:0] dbg_q;
    always @(*) begin
        case (dbg_boff)
            2'd0: dbg_q = mem0[dbg_waddr];
            2'd1: dbg_q = mem1[dbg_waddr];
            2'd2: dbg_q = mem2[dbg_waddr];
            default: dbg_q = mem3[dbg_waddr];
        endcase
    end
    assign dbg_byte_data = dbg_q;

endmodule
