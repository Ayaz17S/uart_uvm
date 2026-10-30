`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 20:36:55
// Design Name: 
// Module Name: baud_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module baud_gen #(parameter int DIV = 4) (
  input  logic clk, rst_n,
  output logic tick16
);
  logic [$clog2(DIV)-1:0] cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cnt <= '0; tick16 <= 1'b0; end
    else begin
      tick16 <= (cnt == DIV-1);
      cnt    <= (cnt == DIV-1) ? '0 : cnt + 1'b1;
    end
  end
endmodule
