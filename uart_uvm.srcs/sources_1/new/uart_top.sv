`timescale 1ns/1ps
module uart_top #(parameter int DIV = 4) (
  input  logic       clk, rst_n,
  input  logic       parity_en,     // 1: frames carry a parity bit
  input  logic       parity_odd,    // 0: even parity, 1: odd parity
  input  logic       tx_valid,
  input  logic [7:0] tx_data,
  output logic       tx_ready,
  output logic       tx_out,
  input  logic       rx_in,
  output logic [7:0] rx_data,
  output logic       rx_valid,
  output logic       frame_err,
  output logic       parity_err
);
  logic tick16;
  baud_gen #(.DIV(DIV)) u_baud (.clk, .rst_n, .tick16);
  uart_tx u_tx (.clk, .rst_n, .tick16, .parity_en, .parity_odd,
                .tx_valid, .tx_data, .tx_ready, .tx_out);
  uart_rx u_rx (.clk, .rst_n, .tick16, .parity_en, .parity_odd,
                .rx_in, .rx_data, .rx_valid, .frame_err, .parity_err);
endmodule
