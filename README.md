# UART with UVM Verification

A small UART (8N1 transmitter + receiver) in SystemVerilog, verified with a UVM 1.2
testbench in the Vivado simulator (XSim). The testbench checks the TX and RX paths
independently, injects framing errors, uses assertions on the interface, and reports
functional coverage.

**Status:** `all_test` passes: 58/58 TX frames, 78/78 RX frames, 0 assertion
failures, 100% functional coverage.

## Design

```
            +-------------------- uart_top --------------------+
            |                                                  |
 clk,rst_n -+-> baud_gen --tick16--+--------------+            |
            |   (DIV clocks/tick)  |              |            |
 tx_valid --+--------------------> uart_tx ---------------------+--> tx_out
 tx_data  --+--------------------> (16 ticks/bit) |            |
 tx_ready <-+--------------------- |              v            |
            |                                  uart_rx <-------+--- rx_in
 rx_data  <-+------------------------------- (2-FF sync,      |
 rx_valid <-+-------------------------------  mid-bit sample) |
 frame_err<-+-------------------------------                   |
            +--------------------------------------------------+
```

| Module | What it does |
|---|---|
| `baud_gen` | Pulses `tick16` every `DIV` clocks (16 ticks per UART bit). |
| `uart_tx` | Valid/ready handshake. Accepts a byte only on a tick so every bit is exactly 16 ticks. Sends start, 8 data bits LSB first, stop. |
| `uart_rx` | 2-FF synchronizer. Rejects start-bit glitches. Samples mid-bit. Pulses `rx_valid` on a good stop bit, `frame_err` on a bad one, then waits for the line to go idle. |
| `uart_top` | Wires the three together. `DIV` is a parameter (default 4). |

With a 100 MHz clock and `DIV = 4`, one bit is 64 clocks (640 ns), about 1.56 Mbaud.

## Testbench

```
 sequences --> sequencer --> driver --+--> TX handshake (tx_valid/tx_data)
                                      +--> RX line (rx_drv) for error injection
                                      |
                       uart_if: rx_in = loopback_en ? tx_out : rx_drv
                                      |
 monitor (3 independent observers):   |
   acc_ap  : bytes the DUT accepted (valid && ready)
   line_ap : frames decoded from the rx_in wire
   out_ap  : what the receiver produced (rx_valid / frame_err)
                 |
                 +--> scoreboard : accepted == wire (TX path)
                 |                 wire == receiver output (RX path)
                 +--> coverage   : data class x gap, bit toggles, good/bad frames
```

- **Loopback by default.** The DUT's `tx_out` feeds its own `rx_in`, so one byte
  exercises both paths.
- **Error injection.** For injected items the driver takes over the RX line and
  drives the frame itself, optionally with a bad stop bit. The scoreboard then
  expects `frame_err` instead of data.
- **Two independent checks.** The TX path is checked against the bytes the DUT
  accepted, and the RX path against what was actually on the wire. A failure
  points to the side that broke.
- **End-of-test checks.** Leftover items in any queue (dropped or spurious
  frames) are errors.
- **Interface assertions.** `tx_valid` held until `tx_ready`, `tx_data` stable
  while waiting, `rx_valid` and `frame_err` never together, and no X on outputs.
  Failures are counted and reported by the scoreboard.
- **Coverage.** 6 data classes (0x00, 0xFF, 0x55, 0xAA, low, high) x 3 gap kinds
  (back-to-back, short, long), plus 0 and 1 on each of the 8 data bits: 34 bins.
  The bins are hand-rolled rather than covergroups, so the report is the same in
  any simulator.

### Tests

| Test | Stimulus |
|---|---|
| `directed_test` | 0x00, 0xFF, 0x55, 0xAA, each with every gap kind (12 frames) |
| `b2b_test` | 32 random bytes back to back |
| `random_test` | 60 random bytes with random gaps |
| `frame_err_test` | 40 frames injected on the RX line, about 30% with a bad stop bit |
| `all_test` | All of the above in one run (default) |

## Running

Requires Vivado 2025.1 (XSim with its bundled UVM 1.2). Other recent versions
should work.

**1. Create the project.** The `.xpr` isn't committed; build it from the script:

```
vivado -mode batch -source create_project.tcl
```

or, in the Vivado Tcl console:

```
cd <path-to-repo>
source create_project.tcl
```

This creates `build/uart_uvm.xpr`, which references the sources in place.

**2. Run the simulation.** Open `build/uart_uvm.xpr` and click *Run Simulation*,
or in the Tcl console:

```
launch_simulation
```

**3. Pick a test.** `tb_top` runs `all_test` by default. To run another one,
pass `+UVM_TESTNAME`:

```
set_property -name xsim.simulate.xsim.more_options -value {-testplusarg UVM_TESTNAME=frame_err_test} -objects [get_filesets sim_1]
```

At the end of the log, look for:

```
[SB] TX path: 58 pass, 0 fail | RX path: 78 pass, 0 fail | other: 0
[SB] *** TEST PASSED ***
```

## Repository layout

```
uart_uvm.srcs/
  sources_1/new/
    baud_gen.sv    uart_tx.sv    uart_rx.sv    uart_top.sv   # RTL
    uart_if.sv                                               # interface, clocking blocks, assertions
    uart_pkg.sv                                              # UVM: items, sequences, agent, scoreboard, coverage, tests
  sim_1/new/
    tb_top.sv      # UVM top: clock, reset, DUT, run_test
    smoke_tb.sv    # plain directed smoke test (no UVM)
create_project.tcl # rebuilds the Vivado project
```

## Roadmap

- [ ] Parity (none / even / odd) with `parity_err` and bad-parity injection
- [ ] Configurable data bits (5-8)
- [ ] 1 or 2 stop bits
- [ ] Break detection, RX FIFO with overrun
