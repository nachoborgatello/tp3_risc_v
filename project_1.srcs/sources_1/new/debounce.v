`timescale 1ns / 1ps

module debounce(
    input wire clk, reset,
    input wire sw,
    output reg db_level, db_tick
    );
    
    // Estados del antirrebote
    localparam [1:0]
        zero  = 2'b00,  // botón liberado
        wait0 = 2'b01,  // espera confirmación de liberado
        one   = 2'b10,  // botón presionado
        wait1 = 2'b11;  // espera confirmación de presionado
    
    localparam N = 20; // determina el tiempo de espera para eliminar rebotes
    
    reg [N-1:0] q_reg, q_next;
    reg [1:0] state_reg, state_next;
    
    // Registro de estado y contador
    always @(posedge clk, posedge reset)
        if (reset)
            begin
                state_reg <= zero;
                q_reg <= 0;
            end
        else
            begin
                state_reg <= state_next;
                q_reg <= q_next;
            end
    
    // Lógica de control antirrebote
    always @*
    begin
        state_next = state_reg;
        q_next = q_reg;
        db_tick = 1'b0;

        case (state_reg)
            zero: // espera botón presionado
                begin
                    db_level = 1'b0;
                    if (sw)
                        begin
                            state_next = wait1;
                            q_next = {N{1'b1}};
                        end
                end

            wait1: // cuenta para confirmar presionado estable
                begin
                    db_level = 1'b0;
                    if (sw)
                        begin
                            q_next = q_reg - 1;
                            if (q_next == 0)
                                begin
                                    state_next = one;
                                    db_tick = 1'b1; // pulso en flanco de subida
                                end
                        end
                    else
                        state_next = zero;
                end

            one: // botón confirmado presionado
                begin
                    db_level = 1'b1;
                    state_next = wait0;
                end

            wait0: // espera confirmación de liberado
                begin
                    db_level = 1'b0;
                    if (~sw)
                        state_next = zero;
                end

            default: state_next = zero;
        endcase
    end      
endmodule

