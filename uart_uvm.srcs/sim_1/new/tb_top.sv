`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 21:07:11
// Design Name: 
// Module Name: tb_top
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


`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uart_pkg::*;

  logic clk = 0;
  always #5 clk = ~clk;

  uart_if vif (clk);

  uart_top #(.DIV(DIV)) dut (
    .clk(clk), .rst_n(vif.rst_n),
    .parity_en(vif.parity_en), .parity_odd(vif.parity_odd), .data_bits(vif.data_bits),
    .tx_valid(vif.tx_valid), .tx_data(vif.tx_data),
    .tx_ready(vif.tx_ready), .tx_out(vif.tx_out),
    .rx_in(vif.rx_in), .rx_data(vif.rx_data),
    .rx_valid(vif.rx_valid), .frame_err(vif.frame_err),
    .parity_err(vif.parity_err));

  initial begin
    vif.rst_n = 0;
    repeat (5) @(negedge clk);
    vif.rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", vif);
    run_test("all_test");
  end

  // global watchdog: a hung test dies with a message instead of running forever
  initial begin
    #4ms;
    `uvm_fatal("WATCHDOG", "simulation timed out")
  end
endmodule
