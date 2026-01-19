`timescale 1ns / 1ps

module mod_m_counter
   #(
    parameter N = 4,  // Cantidad de bits del contador
    parameter M = 10  // Valor del módulo (cuenta de 0 a M-1)
   )
   (
    // Entradas
    input wire clk,
    input wire reset,

    // Salidas
    output wire max_tick, // Pulso alto (1 ciclo de reloj) cuando el contador llega a M-1
    output wire [N-1:0] q // Valor actual del contador
   );

   reg [N-1:0] r_reg;    // Registro que almacena el valor actual del contador
   wire [N-1:0] r_next;  // Señal combinacional con el próximo valor del contador

   always @(posedge clk)
      if (reset)
         r_reg <= 0;
      else
         r_reg <= r_next;

   // Si el contador llegó al valor máximo (M-1), el siguiente valor será 0.
   // De lo contrario, se incrementa en 1.
   assign r_next = (r_reg == (M-1)) ? 0 : r_reg + 1;
   // Señal de "tick" que se pone en 1 sólo cuando el contador alcanza M-1.
   assign max_tick = (r_reg == (M-1)) ? 1'b1 : 1'b0;
   assign q = r_reg;
endmodule
