`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 20:37:30
// Design Name: 
// Module Name: smoke_tb
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


module smoke_tb;
  logic clk = 0, rst_n = 0;
  logic tx_valid = 0, tx_ready, tx_out, rx_valid, frame_err, parity_err;
  logic [7:0] tx_data, rx_data;
  always #5 clk = ~clk;

  uart_top #(.DIV(4)) dut (.clk, .rst_n, .parity_en(1'b1), .parity_odd(1'b0), .data_bits(2'd3),
                           .tx_valid, .tx_data, .tx_ready, .tx_out, .rx_in(tx_out),
                           .rx_data, .rx_valid, .frame_err, .parity_err);

   task automatic send(input logic [7:0] b);
    tx_data  <= b;
    tx_valid <= 1;
    do @(posedge clk); while (!tx_ready);
    tx_valid <= 0;
  endtask

  logic [7:0] vec [4] = '{8'h00, 8'hFF, 8'h55, 8'hA5};
  initial begin
    repeat (4) @(posedge clk); rst_n = 1;
    foreach (vec[i]) send(vec[i]);
    repeat (2000) @(posedge clk);
    $finish;
  end

  always @(posedge clk) begin
    if (rx_valid)  $display("%0t RX got %02h", $time, rx_data);
    if (frame_err) $display("%0t FRAME ERROR", $time);
    if (parity_err) $display("%0t PARITY ERROR", $time);
  end
endmodule
