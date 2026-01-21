`timescale 1ns / 1ps

module debug_unit_uart #(
    parameter DM_DUMP_BYTES = 64
)(
    input  wire clk,
    input  wire reset,

    // UART RX
    input  wire       rx_done_tick,
    input  wire [7:0] rx_dout,

    // UART TX
    output reg        tx_start,
    output reg  [7:0] tx_din,
    input  wire       tx_done_tick,

    // CPU -> DEBUG
    input  wire [31:0]        dbg_pc,
    input  wire              dbg_pipe_empty,
    input  wire              dbg_halt_seen,

    // DEBUG -> CPU
    output reg         dbg_freeze,
    output reg         dbg_run,
    output reg         dbg_step,
    output reg         dbg_drain,

    output reg         dbg_flush_pipe,
    output reg         dbg_load_pc,
    output reg  [31:0] dbg_pc_value,

    output reg         imem_dbg_we,
    output reg  [31:0] imem_dbg_addr,
    output reg  [31:0] imem_dbg_wdata,
    
    // DEBUG -> REGFILE (lectura)
    output reg  [4:0]  rf_dbg_addr,
    input  wire [31:0] rf_dbg_data,
    
    // DEBUG -> DMEM (lectura byte)
    output reg  [11:0] dmem_dbg_addr,   // para BYTES=4096 => 12 bits
    input  wire [7:0]  dmem_dbg_data
);

    // ---------------- estados ----------------
    localparam ST_IDLE   = 4'd0;
    localparam ST_P_ADDR = 4'd1;
    localparam ST_P_DATA = 4'd2;
    localparam ST_RUN    = 4'd3;
    localparam ST_DRAIN  = 4'd4;
    localparam ST_STEP   = 4'd5;
    localparam ST_DUMP   = 4'd6;

    reg [3:0] state;

    reg [2:0]  rx_cnt;
    reg [31:0] rx_addr_buf;
    reg [31:0] rx_data_buf;

    reg [7:0] dump_type; // 1=STEP 2=RUN_END 3=MANUAL

    // TX inflight
    reg tx_inflight;

    // dump index
    localparam integer DUMP_HDR_BYTES = 4;
    localparam integer DUMP_PC_BYTES  = 4;
    localparam integer DUMP_REG_BYTES = 32*4;
    localparam integer DUMP_MEM_BYTES = DM_DUMP_BYTES;
    localparam integer DUMP_TOTAL     = DUMP_HDR_BYTES + DUMP_PC_BYTES + DUMP_REG_BYTES + DUMP_MEM_BYTES;
    localparam ST_STEP_WAIT = 4'd7;

    reg [15:0] dump_idx;
    reg        dump_done;
    reg pending_step_dump;

    
    wire [31:0] addr_next = rx_addr_buf | ({24'b0, rx_dout} << (rx_cnt*8));
    wire [31:0] data_next = rx_data_buf | ({24'b0, rx_dout} << (rx_cnt*8));

    // ============================================================
    // FSM principal (comandos)
    // ============================================================
    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_IDLE;

            dbg_freeze     <= 1'b1;
            dbg_run        <= 1'b0;
            dbg_step       <= 1'b0;
            dbg_drain      <= 1'b0;
            dbg_flush_pipe <= 1'b0;
            dbg_load_pc    <= 1'b0;
            dbg_pc_value   <= 32'b0;

            imem_dbg_we    <= 1'b0;
            imem_dbg_addr  <= 32'b0;
            imem_dbg_wdata <= 32'b0;

            rx_cnt         <= 3'd0;
            rx_addr_buf    <= 32'b0;
            rx_data_buf    <= 32'b0;
            dump_type      <= 8'd0;
            pending_step_dump <= 1'b0;

        end else begin
            // pulsos default
            dbg_step       <= 1'b0;
            dbg_flush_pipe <= 1'b0;
            dbg_load_pc    <= 1'b0;
            imem_dbg_we    <= 1'b0;

            case (state)
                ST_IDLE: begin
                    dbg_freeze <= 1'b1;
                    dbg_run    <= 1'b0;
                    dbg_drain  <= 1'b0;

                    if (rx_done_tick) begin
                        case (rx_dout)
                            "P": begin
                                rx_cnt      <= 3'd0;
                                rx_addr_buf <= 32'b0;
                                rx_data_buf <= 32'b0;
                                state       <= ST_P_ADDR;
                            end
                            "R": begin
                                dbg_pc_value   <= 32'h0000_0000;
                                dbg_flush_pipe <= 1'b1;
                                dbg_load_pc    <= 1'b1;
                            end
                            "T": begin
                                dbg_freeze <= 1'b1;
                            end
                            "D": begin
                                dump_type <= 8'd3;
                                state     <= ST_DUMP;
                            end
                            "S": begin
                                dump_type <= 8'd1;
                                state     <= ST_STEP;
                                pending_step_dump <= 1'b1;
                            end
                            "G": begin
                                state <= ST_RUN;
                                pending_step_dump <= 1'b0;
                            end
                            default: ;
                        endcase
                    end
                end

                ST_P_ADDR: begin
                  if (rx_done_tick) begin
                    rx_addr_buf <= addr_next;
                    if (rx_cnt == 3'd3) begin
                      rx_cnt <= 3'd0;
                      state  <= ST_P_DATA;
                    end else begin
                      rx_cnt <= rx_cnt + 1'b1;
                    end
                  end
                end
                
                ST_P_DATA: begin
                  if (rx_done_tick) begin
                    rx_data_buf <= data_next;
                    if (rx_cnt == 3'd3) begin
                      // IMPORTANTÍSIMO: usar data_next, no rx_data_buf
                      imem_dbg_addr  <= rx_addr_buf; // ya quedó completo en ST_P_ADDR
                      imem_dbg_wdata <= data_next;
                      imem_dbg_we    <= 1'b1;  // pulso de 1 ciclo
                      rx_cnt         <= 3'd0;
                      state          <= ST_IDLE;
                    end else begin
                      rx_cnt <= rx_cnt + 1'b1;
                    end
                  end
                end

                ST_RUN: begin
                    dbg_freeze <= 1'b0;
                    dbg_run    <= 1'b1;

                    if (dbg_halt_seen) begin
                        dbg_run    <= 1'b0;
                        dbg_drain  <= 1'b1;
                        dump_type  <= 8'd2;
                        state      <= ST_DRAIN;
                    end

                end

                ST_DRAIN: begin
                    dbg_freeze <= 1'b0;
                    dbg_drain  <= 1'b1;
                
                    if (dbg_pipe_empty) begin
                        dbg_drain  <= 1'b0;
                        dbg_freeze <= 1'b1;
                        state      <= ST_DUMP;
                        pending_step_dump <= 1'b0;
                    end
                end 

                ST_STEP: begin
                    dbg_freeze <= 1'b0;
                    dbg_step   <= 1'b1;         // pulso 1 ciclo al CPU
                    state      <= ST_STEP_WAIT; // esperamos 1 ciclo para que el avance se "registre"
                end
                
                ST_STEP_WAIT: begin
                    // En este ciclo ya bajamos dbg_step (por default pulse) y dejamos correr 1 ciclo más.
                    // Después drenamos para que el estado quede estable antes del dump.
                    dbg_freeze <= 1'b0;
                    dbg_drain  <= 1'b1;
                    state      <= ST_DRAIN;
                end
                
                ST_DUMP: begin
                    dbg_freeze <= 1'b1;
                    if (dump_done)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // ============================================================
    // TX DUMP FSM  (STREAM: rf_dbg_* y dmem_dbg_*)
    // ============================================================
    
    // pre-cálculos para regs
    wire [15:0] reg_off   = (dump_idx - 16'd8);
    wire [4:0]  reg_idx   = reg_off[15:2]; // /4
    wire [1:0]  reg_byte  = reg_off[1:0];
    
    // pre-cálculos para mem (bytes)
    wire [15:0] mem_off   = dump_idx - (16'd8 + DUMP_REG_BYTES); // 0..DM_DUMP_BYTES-1
    wire [11:0] mem_idx   = mem_off[11:0];
    
    // el dato del reg viene del puerto debug (combinacional)
    wire [31:0] reg_word  = rf_dbg_data;
    
    always @(posedge clk) begin
        if (reset) begin
            tx_start     <= 1'b0;
            tx_din       <= 8'h00;
            tx_inflight  <= 1'b0;
            dump_idx     <= 16'd0;
            dump_done    <= 1'b0;
    
            // direcciones debug en reset
            rf_dbg_addr   <= 5'd0;
            dmem_dbg_addr <= 12'd0;
    
        end else begin
            tx_start  <= 1'b0;
            dump_done <= 1'b0;
    
            if (tx_done_tick)
                tx_inflight <= 1'b0;
    
            if (state == ST_DUMP) begin
                // Mantener direcciones coherentes con dump_idx
                if (dump_idx >= 16'd8 && dump_idx < (16'd8 + DUMP_REG_BYTES))
                    rf_dbg_addr <= reg_idx;
                else
                    rf_dbg_addr <= 5'd0;
    
                if (dump_idx >= (16'd8 + DUMP_REG_BYTES))
                    dmem_dbg_addr <= mem_idx;
                else
                    dmem_dbg_addr <= 12'd0;
    
                if (!tx_inflight) begin
                    // elegir byte a transmitir
                    if (dump_idx < 16'd4) begin
                        case (dump_idx)
                            16'd0: tx_din <= 8'hD0;
                            16'd1: tx_din <= dump_type;
                            16'd2: tx_din <= {6'b0, dbg_pipe_empty, dbg_halt_seen};
                            16'd3: tx_din <= 8'h00;
                            default: tx_din <= 8'h00;
                        endcase
    
                    end else if (dump_idx < 16'd8) begin
                        case (dump_idx - 16'd4)
                            16'd0: tx_din <= dbg_pc[7:0];
                            16'd1: tx_din <= dbg_pc[15:8];
                            16'd2: tx_din <= dbg_pc[23:16];
                            16'd3: tx_din <= dbg_pc[31:24];
                            default: tx_din <= 8'h00;
                        endcase
    
                    end else if (dump_idx < (16'd8 + DUMP_REG_BYTES)) begin
                        case (reg_byte)
                            2'd0: tx_din <= reg_word[7:0];
                            2'd1: tx_din <= reg_word[15:8];
                            2'd2: tx_din <= reg_word[23:16];
                            2'd3: tx_din <= reg_word[31:24];
                            default: tx_din <= 8'h00;
                        endcase
    
                    end else begin
                        // bytes de DMEM: vienen del puerto dmem_dbg_data
                        tx_din <= dmem_dbg_data;
                    end
    
                    tx_start    <= 1'b1;
                    tx_inflight <= 1'b1;
    
                    if (dump_idx == DUMP_TOTAL-1) begin
                        dump_idx  <= 16'd0;
                        dump_done <= 1'b1;
                    end else begin
                        dump_idx <= dump_idx + 1'b1;
                    end
                end
            end else begin
                dump_idx <= 16'd0;
    
                // Opcional: estacionar direcciones
                rf_dbg_addr   <= 5'd0;
                dmem_dbg_addr <= 12'd0;
            end
        end
end


endmodule
