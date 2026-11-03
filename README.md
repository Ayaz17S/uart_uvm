# UART with UVM Verification

A small UART (transmitter + receiver, 5-8 data bits, optional even/odd parity, 1 or 2
stop bits) in SystemVerilog, verified with a UVM 1.2 testbench in the Vivado
simulator (XSim). The testbench checks the TX and RX paths independently, injects
framing and parity errors, uses assertions on the interface, and reports functional
coverage.

**Status:** `all_test` passes in all 24 formats (5-8 data bits x parity none, even,
odd x 1 or 2 stop bits): 58/58 TX frames, 88/88 RX frames, 0 assertion failures,
100% functional coverage.

## Design

```
             +-------------------- uart_top --------------------+
             |                                                  |
 clk,rst_n --+-> baud_gen --tick16--+--------------+            |
             |   (DIV clocks/tick)  |              |            |
 parity_en --+----------------------+--------------+            |
 parity_odd -+----------------------+--------------+            |
 data_bits --+----------------------+--------------+            |
 stop2     --+----------------------+ (TX only)                 |
 tx_valid  --+--------------------> uart_tx ---------------------+--> tx_out
 tx_data   --+--------------------> (16 ticks/bit) |            |
 tx_ready  <-+--------------------- |              v            |
             |                                  uart_rx <-------+--- rx_in
 rx_data   <-+------------------------------- (2-FF sync,      |
 rx_valid  <-+-------------------------------  mid-bit sample) |
 frame_err <-+-------------------------------                   |
 parity_err<-+-------------------------------                   |
             +--------------------------------------------------+
```

Frame: start, 5-8 data bits LSB first, parity bit (if `parity_en`), 1 or 2 stop bits.

| Module | What it does |
|---|---|
| `baud_gen` | Pulses `tick16` every `DIV` clocks (16 ticks per UART bit). |
| `uart_tx` | Valid/ready handshake. Accepts a byte only on a tick so every bit is exactly 16 ticks. Sends the low `data_bits + 5` bits of `tx_data` and ignores the rest. Computes the parity bit over the sent bits when the byte is accepted. Holds the line high for 1 or 2 stop bits before accepting the next byte. |
| `uart_rx` | 2-FF synchronizer. Rejects start-bit glitches. Samples mid-bit. `rx_data` is right-aligned with the unused high bits 0. At the stop bit it pulses `frame_err` (stop bit low) and/or `parity_err` (parity mismatch) independently; `rx_valid` only if neither. Checks only the first stop bit (like a 16550), so it is ready for the next start bit right after it. After a bad stop bit it waits for the line to go idle. |
| `uart_top` | Wires the three together. `DIV` is a parameter (default 4). |

The frame config is latched at the start of each frame:

| Input | Meaning |
|---|---|
| `data_bits[1:0]` | 0, 1, 2, 3 = 5, 6, 7, 8 data bits (same encoding as a 16550) |
| `parity_en` | 1 = add a parity bit after the data |
| `parity_odd` | 0 = even parity, 1 = odd parity |
| `stop2` | 0 = 1 stop bit, 1 = 2 stop bits (transmitter only) |

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
                 +--> coverage   : data class x gap, bit toggles, error kinds
```

- **Frame format per run.** The test reads `+DATA_BITS=5..8` (default 8),
  `+PARITY=none|even|odd` (default even) and `+STOP_BITS=1|2` (default 1) and sets
  them on the interface before reset is released. The driver, monitor, scoreboard
  and coverage all follow them.
- **Loopback by default.** The DUT's `tx_out` feeds its own `rx_in`, so one byte
  exercises both paths.
- **Error injection.** For injected items the driver takes over the RX line and
  drives the frame itself, optionally with a bad stop bit, a flipped parity bit,
  or both. The scoreboard then expects no data and exactly the matching
  `frame_err` / `parity_err` flags. The sequence starts with one frame of each
  enabled error kind, so coverage doesn't depend on the random seed. Good frames
  go back to back; with 2 stop bits, some are sent with only one, and the
  receiver must still take them.
- **Stop bits on the TX side.** With 2 stop bits, the monitor samples the second
  stop bit of every frame from the DUT's transmitter; a low there fails the TX
  check.
- **Two independent checks.** The TX path is checked against the bytes the DUT
  accepted, and the RX path against what was actually on the wire. A failure
  points to the side that broke.
- **End-of-test checks.** Leftover items in any queue (dropped or spurious
  frames) are errors.
- **Interface assertions.** `tx_valid` held until `tx_ready`, `tx_data` stable
  while waiting, `rx_valid` never together with an error flag, no `parity_err`
  with parity off, frame config stable, `rx_data` right-aligned (no bits above
  the data width), and no X on outputs. Failures are counted and reported by the
  scoreboard.
- **Coverage.** 6 data classes (zero, all ones, 0x55 and 0xAA patterns, low,
  high; all cut to the configured width) x 3 gap kinds (back-to-back, short,
  long), 0 and 1 on each data bit, and the error kind of each wire frame (good,
  bad stop, plus bad parity and both when parity is on), plus one bin for
  1-stop frames into the receiver when it is set for 2. That is 39 bins at 8
  bits with parity and 2 stop bits, down to 30 at 5 bits, no parity, 1 stop. The bins are hand-rolled
  rather than covergroups, so the report is the same in any simulator.
- **Checked against planted bugs.** With the receiver's odd-parity handling
  broken on purpose, `all_test +PARITY=odd` fails with `RX_MISMATCH` errors.
  With the receiver's right-alignment removed, `all_test +DATA_BITS=6` fails 78
  of 88 RX frames and the alignment assertion fires. With the transmitter's
  second stop bit removed, `all_test +STOP_BITS=2` fails every TX frame with
  `stop2_ok=0`.

### Tests

| Test | Stimulus |
|---|---|
| `directed_test` | 0x00, 0xFF, 0x55, 0xAA, each with every gap kind (12 frames) |
| `b2b_test` | 32 random bytes back to back |
| `random_test` | 60 random bytes with random gaps |
| `frame_err_test` | 40 frames injected on the RX line, about 30% with a bad stop bit |
| `parity_err_test` | 40 injected frames, about 50% with a flipped parity bit (needs parity on) |
| `all_test` | Directed, back-to-back, random, then 30 injected frames with bad stop and/or parity (default) |

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

**3. Pick a test and frame format.** `tb_top` runs `all_test` with 8 data bits,
even parity and 1 stop bit by default. Pass `+UVM_TESTNAME`, `+DATA_BITS`,
`+PARITY` and/or `+STOP_BITS` to change that:

```
set_property -name xsim.simulate.xsim.more_options -value {-testplusarg UVM_TESTNAME=parity_err_test -testplusarg DATA_BITS=6 -testplusarg PARITY=odd -testplusarg STOP_BITS=2} -objects [get_filesets sim_1]
```

At the end of the log, look for:

```
[CFG] frame format: 8 data bits, parity=even, 1 stop bit
[SB] TX path: 58 pass, 0 fail | RX path: 88 pass, 0 fail | other: 0
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

- [x] Parity (none / even / odd) with `parity_err` and bad-parity injection
- [x] Configurable data bits (5-8)
- [x] 1 or 2 stop bits
- [ ] Break detection, RX FIFO with overrun

## Future work

Ideas for extending the design and the testbench:

- **Break detection.** Recognise the line held low for a whole frame or longer
  and report a break instead of a framing error. Test it by injecting long low
  periods of different lengths.
- **RX FIFO with overrun.** Buffer received bytes behind a read interface and
  flag bytes dropped when the FIFO is full. The scoreboard would then need to
  model the FIFO and predict exactly which bytes are lost.
- **Runtime baud rate and clock mismatch.** Replace the `DIV` parameter with a
  divisor input so tests can change the rate, and check that the receiver still
  works when the sender's clock is a few percent off.
- **Covergroups.** Move the hand-rolled coverage bins to SystemVerilog
  covergroups, with a cross of data width, parity and stop bits, for simulators
  with full coverage support.
- **Regression script.** Run every frame format over several random seeds with
  one command and print a pass/fail summary.
- **Synthesis results.** Synthesize `uart_top` for a target FPGA and report
  resource use and maximum clock frequency.
