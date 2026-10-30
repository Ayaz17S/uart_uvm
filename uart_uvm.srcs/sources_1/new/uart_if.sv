`timescale 1ns/1ps
interface uart_if (input logic clk);
  logic       rst_n = 0;
  // Frame config: set by the test before reset is released, then held
  logic       parity_en  = 0;
  logic       parity_odd = 0;
  logic [1:0] data_bits  = 2'd3;   // 0..3 = 5..8 data bits
  logic       stop2      = 0;      // 0: 1 stop bit, 1: 2 stop bits (TX)
  // TX side
  logic       tx_valid = 0;
  logic [7:0] tx_data  = '0;
  logic       tx_ready;
  logic       tx_out;
  // RX side
  logic       rx_in;
  logic [7:0] rx_data;
  logic       rx_valid;
  logic       frame_err;
  logic       parity_err;
  // RX line control: loopback by default, TB-driven for error injection
  logic       loopback_en = 1;
  logic       rx_drv      = 1;
  assign rx_in = loopback_en ? tx_out : rx_drv;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output tx_valid, tx_data, loopback_en, rx_drv;
    input  tx_ready;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input tx_valid, tx_data, tx_ready, tx_out,
          rx_in, rx_data, rx_valid, frame_err, parity_err;
  endclocking

  // ------------------------------------------------------------
  // Protocol assertions; failures are counted for the scoreboard
  // ------------------------------------------------------------
  int unsigned assert_errors = 0;

  // valid must stay high until the DUT takes the byte
  a_valid_hold: assert property (@(posedge clk) disable iff (!rst_n)
                  tx_valid && !tx_ready |=> tx_valid)
    else begin assert_errors++; $error("tx_valid dropped before tx_ready"); end

  // data must stay stable while waiting for ready
  a_data_stable: assert property (@(posedge clk) disable iff (!rst_n)
                  tx_valid && !tx_ready |=> $stable(tx_data))
    else begin assert_errors++; $error("tx_data changed while waiting for tx_ready"); end

  // receiver never reports good data and an error at the same time
  a_rx_excl: assert property (@(posedge clk) disable iff (!rst_n)
                  !(rx_valid && (frame_err || parity_err)))
    else begin assert_errors++; $error("rx_valid high together with frame_err/parity_err"); end

  // no parity error can be reported while parity is disabled
  a_no_par_err: assert property (@(posedge clk) disable iff (!rst_n)
                  !parity_en |-> !parity_err)
    else begin assert_errors++; $error("parity_err with parity disabled"); end

  // frame config must not change while out of reset
  a_cfg_stable: assert property (@(posedge clk) disable iff (!rst_n)
                  $stable({parity_en, parity_odd, data_bits, stop2}))
    else begin assert_errors++; $error("frame config changed during operation"); end

  // received data is right-aligned: bits above the configured width are 0
  a_rx_aligned: assert property (@(posedge clk) disable iff (!rst_n)
                  rx_valid |-> (rx_data >> (data_bits + 5)) == 0)
    else begin assert_errors++; $error("rx_data has bits set above the data width"); end

  // no X on outputs after reset
  a_no_x: assert property (@(posedge clk) disable iff (!rst_n)
                  !$isunknown({tx_ready, tx_out, rx_valid, frame_err, parity_err}))
    else begin assert_errors++; $error("X on a DUT output"); end
endinterface
