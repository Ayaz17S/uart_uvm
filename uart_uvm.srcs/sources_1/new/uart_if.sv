`timescale 1ns/1ps
interface uart_if (input logic clk);
  logic       rst_n = 0;
  // Frame config: set by the test before reset is released, then held
  logic       parity_en  = 0;
  logic       parity_odd = 0;
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
                  $stable({parity_en, parity_odd}))
    else begin assert_errors++; $error("parity config changed during operation"); end

  // no X on outputs after reset
  a_no_x: assert property (@(posedge clk) disable iff (!rst_n)
                  !$isunknown({tx_ready, tx_out, rx_valid, frame_err, parity_err}))
    else begin assert_errors++; $error("X on a DUT output"); end
endinterface
