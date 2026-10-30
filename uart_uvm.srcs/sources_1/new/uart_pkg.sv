`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.10.2026 21:05:54
// Design Name: 
// Module Name: uart_pkg
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


package uart_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  parameter int DIV      = 4;          // clocks per tick16 (also used by tb_top)
  parameter int BIT_CLKS = DIV * 16;   // clocks per UART bit

  `uvm_analysis_imp_decl(_acc)
  `uvm_analysis_imp_decl(_line)
  `uvm_analysis_imp_decl(_out)
  `uvm_analysis_imp_decl(_cline)

  // ===============================================================
  // Stimulus item
  // ===============================================================
  class uart_item extends uvm_sequence_item;
    rand bit [7:0]  data;
    rand bit [1:0]  gap_kind;    // 0: back-to-back, 1: short, 2: long
    rand bit [15:0] gap;         // idle clocks before the item
    bit inject;                  // 0: send via TX path, 1: drive the RX line directly
    bit bad_stop;                // inject only: stop bit forced to 0 (framing error)

    constraint c_gap_kind { gap_kind inside {[0:2]}; }
    constraint c_gap {
      solve gap_kind before gap;
      (gap_kind == 0) -> gap == 0;
      (gap_kind == 1) -> gap inside {[1:20]};
      (gap_kind == 2) -> gap inside {[21:200]};
    }

    `uvm_object_utils(uart_item)
    function new(string name = "uart_item");
      super.new(name);
    endfunction

    virtual function string convert2string();
      return $sformatf("%s data=0x%02h gap=%0d%s", inject ? "INJECT" : "TX",
                       data, gap, bad_stop ? " BAD_STOP" : "");
    endfunction
  endclass

  // ===============================================================
  // Sequences
  // ===============================================================
  class uart_base_seq extends uvm_sequence #(uart_item);
    `uvm_object_utils(uart_base_seq)
    function new(string name = "uart_base_seq");
      super.new(name);
    endfunction
  endclass

  // Corner values x every gap kind
  class uart_directed_seq extends uart_base_seq;
    `uvm_object_utils(uart_directed_seq)
    bit [7:0] vec[$] = '{8'h00, 8'hFF, 8'h55, 8'hAA};
    function new(string name = "uart_directed_seq");
      super.new(name);
    endfunction
    virtual task body();
      foreach (vec[i]) begin
        for (int k = 0; k < 3; k++) begin
          bit [7:0] val    = vec[i];
          bit [1:0] want_g = k;
          req = uart_item::type_id::create($sformatf("it%0d_%0d", i, k));
          start_item(req);
          if (!req.randomize() with { data == val; gap_kind == want_g; })
            `uvm_fatal("RAND", "randomize failed")
          finish_item(req);
        end
      end
    endtask
  endclass

  // Random data, zero gap
  class uart_b2b_seq extends uart_base_seq;
    `uvm_object_utils(uart_b2b_seq)
    int unsigned count = 16;
    function new(string name = "uart_b2b_seq");
      super.new(name);
    endfunction
    virtual task body();
      repeat (count) begin
        req = uart_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { gap == 0; })
          `uvm_fatal("RAND", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  // Fully random data and gaps
  class uart_random_seq extends uart_base_seq;
    `uvm_object_utils(uart_random_seq)
    int unsigned count = 30;
    function new(string name = "uart_random_seq");
      super.new(name);
    endfunction
    virtual task body();
      repeat (count) begin
        req = uart_item::type_id::create("req");
        start_item(req);
        if (!req.randomize())
          `uvm_fatal("RAND", "randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  // Frames driven straight onto the RX line, some with a bad stop bit
  class uart_inject_seq extends uart_base_seq;
    `uvm_object_utils(uart_inject_seq)
    int unsigned count   = 20;
    int unsigned bad_pct = 30;
    function new(string name = "uart_inject_seq");
      super.new(name);
    endfunction
    virtual task body();
      repeat (count) begin
        req = uart_item::type_id::create("req");
        start_item(req);
        if (!req.randomize())
          `uvm_fatal("RAND", "randomize failed")
        req.inject   = 1'b1;
        req.bad_stop = ($urandom_range(99) < bad_pct);
        finish_item(req);
      end
    endtask
  endclass

  // ===============================================================
  // Observation item (what the monitor publishes)
  // ===============================================================
  typedef enum {OBS_ACCEPT, OBS_FRAME, OBS_OUT_DATA, OBS_OUT_ERR} obs_kind_e;

  class uart_obs extends uvm_object;
    obs_kind_e kind;
    bit [7:0]  data;
    bit        stop_ok;     // OBS_FRAME: stop bit was high
    bit        via_loop;    // OBS_FRAME: frame came from the DUT's own TX
    time       t;
    `uvm_object_utils(uart_obs)
    function new(string name = "uart_obs");
      super.new(name);
    endfunction
    virtual function string convert2string();
      return $sformatf("%s data=0x%02h stop_ok=%0b @%0t", kind.name(), data, stop_ok, t);
    endfunction
  endclass

  typedef uvm_sequencer #(uart_item) uart_sequencer;

  // ===============================================================
  // Driver
  // ===============================================================
  class uart_driver extends uvm_driver #(uart_item);
    `uvm_component_utils(uart_driver)
    virtual uart_if vif;
    uvm_analysis_port #(uart_item) item_ap;
    bit last_was_tx;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      item_ap = new("item_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
      vif.drv_cb.tx_valid <= 1'b0;
      vif.drv_cb.tx_data  <= '0;
      wait (vif.rst_n === 1'b1);
      @(vif.drv_cb);
      forever begin
        seq_item_port.get_next_item(req);
        if (req.inject) drive_inject(req);
        else            drive_tx(req);
        item_ap.write(req);
        seq_item_port.item_done();
      end
    endtask

    // Normal path: handshake a byte into the DUT's transmitter
    task drive_tx(uart_item it);
      int unsigned t = 0;
      `uvm_info("DRV", $sformatf("send %s", it.convert2string()), UVM_MEDIUM)
      last_was_tx = 1'b1;
      vif.drv_cb.loopback_en <= 1'b1;
      repeat (it.gap) @(vif.drv_cb);
      vif.drv_cb.tx_data  <= it.data;
      vif.drv_cb.tx_valid <= 1'b1;
      do begin
        @(vif.drv_cb);
        if (++t > 5000) begin
          `uvm_error("DRV", "timeout waiting for tx_ready")
          break;
        end
      end while (!vif.drv_cb.tx_ready);
      vif.drv_cb.tx_valid <= 1'b0;
    endtask

    // Error path: drive a frame on the RX line ourselves
    task drive_inject(uart_item it);
      `uvm_info("DRV", $sformatf("send %s", it.convert2string()), UVM_MEDIUM)
      if (last_was_tx)   // let any in-flight TX frame finish before leaving loopback
        repeat (11 * BIT_CLKS) @(vif.drv_cb);
      last_was_tx = 1'b0;
      vif.drv_cb.loopback_en <= 1'b0;
      repeat (it.gap + 1) @(vif.drv_cb);
      vif.drv_cb.rx_drv <= 1'b0;                      // start
      repeat (BIT_CLKS) @(vif.drv_cb);
      for (int i = 0; i < 8; i++) begin               // data, LSB first
        vif.drv_cb.rx_drv <= it.data[i];
        repeat (BIT_CLKS) @(vif.drv_cb);
      end
      vif.drv_cb.rx_drv <= it.bad_stop ? 1'b0 : 1'b1; // stop
      repeat (BIT_CLKS) @(vif.drv_cb);
      vif.drv_cb.rx_drv <= 1'b1;                      // idle
      repeat (2 * BIT_CLKS) @(vif.drv_cb);
    endtask
  endclass

  // ===============================================================
  // Monitor: three independent observers
  // ===============================================================
  class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)
    virtual uart_if vif;
    uvm_analysis_port #(uart_obs) acc_ap;    // bytes the DUT accepted for TX
    uvm_analysis_port #(uart_obs) line_ap;   // frames decoded from the rx_in wire
    uvm_analysis_port #(uart_obs) out_ap;    // what the DUT receiver produced

    function new(string name, uvm_component parent);
      super.new(name, parent);
      acc_ap  = new("acc_ap",  this);
      line_ap = new("line_ap", this);
      out_ap  = new("out_ap",  this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
      wait (vif.rst_n === 1'b1);
      fork
        mon_accept();
        mon_line();
        mon_output();
      join
    endtask

    // A byte is accepted when valid && ready are both high at a clock edge
    task mon_accept();
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.tx_valid && vif.mon_cb.tx_ready) begin
          uart_obs o = uart_obs::type_id::create("acc");
          o.kind = OBS_ACCEPT;
          o.data = vif.mon_cb.tx_data;
          o.t    = $time;
          acc_ap.write(o);
        end
      end
    endtask

    // Decode serial frames from the line, sampling in the middle of each bit
    task mon_line();
      bit       prev = 1'b1;
      bit [7:0] d;
      bit       ok;
      uart_obs  o;
      forever begin
        @(vif.mon_cb);
        if (prev && !vif.mon_cb.rx_in) begin
          o = uart_obs::type_id::create("frame");
          o.via_loop = vif.loopback_en;
          repeat (BIT_CLKS / 2) @(vif.mon_cb);
          if (vif.mon_cb.rx_in) begin     // glitch, not a real start bit
            prev = 1'b1;
            continue;
          end
          for (int i = 0; i < 8; i++) begin
            repeat (BIT_CLKS) @(vif.mon_cb);
            d[i] = vif.mon_cb.rx_in;
          end
          repeat (BIT_CLKS) @(vif.mon_cb);
          ok = vif.mon_cb.rx_in;
          o.kind    = OBS_FRAME;
          o.data    = d;
          o.stop_ok = ok;
          o.t       = $time;
          line_ap.write(o);
          while (!vif.mon_cb.rx_in) @(vif.mon_cb);   // wait for idle after a bad stop
          prev = 1'b1;
        end else
          prev = vif.mon_cb.rx_in;
      end
    endtask

    task mon_output();
      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.rx_valid) begin
          uart_obs o = uart_obs::type_id::create("out");
          o.kind = OBS_OUT_DATA;
          o.data = vif.mon_cb.rx_data;
          o.t    = $time;
          out_ap.write(o);
        end
        if (vif.mon_cb.frame_err) begin
          uart_obs e = uart_obs::type_id::create("err");
          e.kind = OBS_OUT_ERR;
          e.t    = $time;
          out_ap.write(e);
        end
      end
    endtask
  endclass

  // ===============================================================
  // Scoreboard
  // ===============================================================
  class uart_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_scoreboard)
    uvm_analysis_imp_acc  #(uart_obs, uart_scoreboard) acc_imp;
    uvm_analysis_imp_line #(uart_obs, uart_scoreboard) line_imp;
    uvm_analysis_imp_out  #(uart_obs, uart_scoreboard) out_imp;

    virtual uart_if vif;
    uart_obs acc_q[$], line_tx_q[$], line_rx_q[$], out_q[$];
    int unsigned out_count, tx_pass, tx_fail, rx_pass, rx_fail, other_err;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      acc_imp  = new("acc_imp",  this);
      line_imp = new("line_imp", this);
      out_imp  = new("out_imp",  this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for scoreboard")
    endfunction

    function void write_acc(uart_obs o);
      acc_q.push_back(o);
      check_tx();
    endfunction

    function void write_line(uart_obs o);
      line_rx_q.push_back(o);
      if (o.via_loop) line_tx_q.push_back(o);
      check_tx();
      check_rx();
    endfunction

    function void write_out(uart_obs o);
      out_q.push_back(o);
      out_count++;
      check_rx();
    endfunction

    // TX path: accepted byte must appear on the wire, correctly framed
    function void check_tx();
      uart_obs a, l;
      while (acc_q.size() > 0 && line_tx_q.size() > 0) begin
        a = acc_q.pop_front();
        l = line_tx_q.pop_front();
        if (a.data !== l.data || !l.stop_ok) begin
          tx_fail++;
          `uvm_error("TX_MISMATCH", $sformatf("accepted 0x%02h but wire shows 0x%02h (stop_ok=%0b)",
                                              a.data, l.data, l.stop_ok))
        end else tx_pass++;
      end
    endfunction

    // RX path: every wire frame must come out of the receiver
    function void check_rx();
      uart_obs l, o;
      while (line_rx_q.size() > 0 && out_q.size() > 0) begin
        l = line_rx_q.pop_front();
        o = out_q.pop_front();
        if (l.stop_ok) begin
          if (o.kind != OBS_OUT_DATA || o.data !== l.data) begin
            rx_fail++;
            `uvm_error("RX_MISMATCH", $sformatf("wire: %s | DUT: %s", l.convert2string(), o.convert2string()))
          end else rx_pass++;
        end else begin
          if (o.kind != OBS_OUT_ERR) begin
            rx_fail++;
            `uvm_error("RX_NO_FRAME_ERR", $sformatf("bad stop bit on wire (%s) but DUT said: %s",
                                                    l.convert2string(), o.convert2string()))
          end else rx_pass++;
        end
      end
    endfunction

    function void check_phase(uvm_phase phase);
      if (acc_q.size() > 0) begin
        other_err++;
        `uvm_error("LEFTOVER", $sformatf("%0d accepted byte(s) never appeared on the wire", acc_q.size()))
      end
      if (line_tx_q.size() > 0) begin
        other_err++;
        `uvm_error("LEFTOVER", $sformatf("%0d wire frame(s) with no accepted byte", line_tx_q.size()))
      end
      if (line_rx_q.size() > 0) begin
        other_err++;
        `uvm_error("LEFTOVER", $sformatf("%0d wire frame(s) with no DUT output (dropped)", line_rx_q.size()))
      end
      if (out_q.size() > 0) begin
        other_err++;
        `uvm_error("LEFTOVER", $sformatf("%0d DUT output(s) with no wire frame (spurious)", out_q.size()))
      end
      if (vif.assert_errors > 0) begin
        other_err++;
        `uvm_error("ASSERT", $sformatf("%0d interface assertion failure(s)", vif.assert_errors))
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SB", $sformatf("TX path: %0d pass, %0d fail | RX path: %0d pass, %0d fail | other: %0d",
                tx_pass, tx_fail, rx_pass, rx_fail, other_err), UVM_NONE)
      if (tx_fail == 0 && rx_fail == 0 && other_err == 0 && (tx_pass + rx_pass) > 0)
        `uvm_info("SB", "*** TEST PASSED ***", UVM_NONE)
      else
        `uvm_error("SB", "*** TEST FAILED ***")
    endfunction
  endclass

  // ===============================================================
  // Functional coverage (hand-rolled bins, so it works in any simulator)
  // ===============================================================
  class uart_coverage extends uvm_component;
    `uvm_component_utils(uart_coverage)
    uvm_analysis_imp       #(uart_item, uart_coverage) item_imp;
    uvm_analysis_imp_cline #(uart_obs,  uart_coverage) line_imp;

    int unsigned hits[string];
    bit seen0[8], seen1[8];
    int unsigned frames_ok, frames_bad;
    string data_bins[$] = '{"zero", "ones", "a55", "aAA", "low", "high"};
    string gap_bins[$]  = '{"b2b", "short", "long"};

    function new(string name, uvm_component parent);
      super.new(name, parent);
      item_imp = new("item_imp", this);
      line_imp = new("line_imp", this);
    endfunction

    function string data_bin(bit [7:0] d);
      if      (d == 8'h00) return "zero";
      else if (d == 8'hFF) return "ones";
      else if (d == 8'h55) return "a55";
      else if (d == 8'hAA) return "aAA";
      else if (d < 8'h80)  return "low";
      else                 return "high";
    endfunction

    function string gap_bin(bit [1:0] g);
      case (g)
        2'd0:    return "b2b";
        2'd1:    return "short";
        default: return "long";
      endcase
    endfunction

    function void write(uart_item t);
      string key;
      if (t.inject) return;
      key = {data_bin(t.data), ":", gap_bin(t.gap_kind)};
      if (!hits.exists(key)) hits[key] = 0;
      hits[key]++;
      for (int i = 0; i < 8; i++) begin
        if (t.data[i]) seen1[i] = 1'b1;
        else           seen0[i] = 1'b1;
      end
    endfunction

    function void write_cline(uart_obs o);
      if (o.stop_ok) frames_ok++;
      else           frames_bad++;
    endfunction

        function void report_phase(uvm_phase phase);
      string s;
      int covered = 0, total = 0;
      real pct;
      s = "\n  data \\ gap    b2b  short   long\n";
      foreach (data_bins[i]) begin
        s = {s, $sformatf("  %-10s", data_bins[i])};
        foreach (gap_bins[j]) begin
          string key = {data_bins[i], ":", gap_bins[j]};
          int n = hits.exists(key) ? hits[key] : 0;
          s = {s, $sformatf(" %6d", n)};
          total++;
          if (n > 0) covered++;
        end
        s = {s, "\n"};
      end
      for (int i = 0; i < 8; i++) begin
        total += 2;
        if (seen0[i]) covered++;
        if (seen1[i]) covered++;
      end
      pct = (total == 0) ? 0.0 : (100.0 * covered / total);
      begin
        int tog = 0;
        for (int i = 0; i < 8; i++) begin
          if (seen0[i]) tog++;
          if (seen1[i]) tog++;
        end
        s = {s, $sformatf("  bit toggles (0 and 1 on each of 8 bits): %0d/16 bins\n", tog)};
      end
      s = {s, $sformatf("  wire frames: %0d good, %0d bad stop bit\n", frames_ok, frames_bad)};
      s = {s, $sformatf("  functional coverage: %0d/%0d bins = %0.1f%%", covered, total, pct)};
      `uvm_info("COV", s, UVM_NONE)
    endfunction
  endclass

  // ===============================================================
  // Agent + environment
  // ===============================================================
  class uart_agent extends uvm_agent;
    `uvm_component_utils(uart_agent)
    uart_sequencer sqr;
    uart_driver    drv;
    uart_monitor   mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = uart_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sqr = uart_sequencer::type_id::create("sqr", this);
        drv = uart_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class uart_env extends uvm_env;
    `uvm_component_utils(uart_env)
    uart_agent      agent;
    uart_scoreboard sb;
    uart_coverage   cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = uart_agent::type_id::create("agent", this);
      sb    = uart_scoreboard::type_id::create("sb", this);
      cov   = uart_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.acc_ap.connect(sb.acc_imp);
      agent.mon.line_ap.connect(sb.line_imp);
      agent.mon.out_ap.connect(sb.out_imp);
      agent.drv.item_ap.connect(cov.item_imp);
      agent.mon.line_ap.connect(cov.line_imp);
    endfunction
  endclass

  // ===============================================================
  // Tests
  // ===============================================================
  class uart_base_test extends uvm_test;
    `uvm_component_utils(uart_base_test)
    uart_env env;
    virtual uart_if vif;
    int unsigned total_frames;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set for test")
      env = uart_env::type_id::create("env", this);
    endfunction

    // Run a sequence, then wait until the DUT has produced one output per frame
    task run_and_drain(uart_base_seq seq, int unsigned n_frames);
      total_frames += n_frames;
      seq.start(env.agent.sqr);
      fork
        wait (env.sb.out_count >= total_frames);
        begin
          repeat (n_frames * 2000 + 5000) @(posedge vif.clk);
          `uvm_error("TIMEOUT", "DUT did not produce the expected number of outputs")
        end
      join_any
      disable fork;
      repeat (200) @(posedge vif.clk);   // settle: catch late or spurious outputs
    endtask
  endclass

  class directed_test extends uart_base_test;
    `uvm_component_utils(directed_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      uart_directed_seq s = uart_directed_seq::type_id::create("s");
      phase.raise_objection(this);
      run_and_drain(s, 12);
      phase.drop_objection(this);
    endtask
  endclass

  class b2b_test extends uart_base_test;
    `uvm_component_utils(b2b_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      uart_b2b_seq s = uart_b2b_seq::type_id::create("s");
      s.count = 32;
      phase.raise_objection(this);
      run_and_drain(s, 32);
      phase.drop_objection(this);
    endtask
  endclass

  class random_test extends uart_base_test;
    `uvm_component_utils(random_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      uart_random_seq s = uart_random_seq::type_id::create("s");
      s.count = 60;
      phase.raise_objection(this);
      run_and_drain(s, 60);
      phase.drop_objection(this);
    endtask
  endclass

  class frame_err_test extends uart_base_test;
    `uvm_component_utils(frame_err_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      uart_inject_seq s = uart_inject_seq::type_id::create("s");
      s.count = 40;
      phase.raise_objection(this);
      run_and_drain(s, 40);
      phase.drop_objection(this);
    endtask
  endclass

  // Everything in one run
  class all_test extends uart_base_test;
    `uvm_component_utils(all_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      uart_directed_seq d = uart_directed_seq::type_id::create("d");
      uart_b2b_seq      b = uart_b2b_seq::type_id::create("b");
      uart_random_seq   r = uart_random_seq::type_id::create("r");
      uart_inject_seq   e = uart_inject_seq::type_id::create("e");
      b.count = 16;
      r.count = 30;
      e.count = 20;
      phase.raise_objection(this);
      run_and_drain(d, 12);
      run_and_drain(b, 16);
      run_and_drain(r, 30);
      run_and_drain(e, 20);
      phase.drop_objection(this);
    endtask
  endclass
endpackage
