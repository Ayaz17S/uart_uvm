`timescale 1ns/1ps
module uart_rx (
  input  logic       clk, rst_n, tick16,
  input  logic       parity_en,     // 1: expect a parity bit after the data
  input  logic       parity_odd,    // 0: even parity, 1: odd parity
  input  logic [1:0] data_bits,     // 0..3 = 5..8 data bits; rx_data is right-aligned
  input  logic       rx_in,
  output logic [7:0] rx_data,
  output logic       rx_valid,
  output logic       frame_err,
  output logic       parity_err
);
  typedef enum logic [2:0] {IDLE, START, DATA, PARITY, STOP, WAIT_HIGH} state_t;
  state_t     state;
  logic [3:0] tcnt;
  logic [2:0] bit_idx;
  logic [7:0] shreg;
  logic       rx_s1, rx_s;          // 2-FF synchronizer
  logic       par_en_q, par_odd_q;  // parity config latched for the whole frame
  logic [1:0] nb_q;                 // data_bits latched for the whole frame
  logic       par_bad;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rx_s1 <= 1'b1; rx_s <= 1'b1; end
    else        begin rx_s1 <= rx_in; rx_s <= rx_s1; end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE; tcnt <= '0; bit_idx <= '0; shreg <= '0;
      rx_data <= '0; rx_valid <= 1'b0; frame_err <= 1'b0; parity_err <= 1'b0;
      par_en_q <= 1'b0; par_odd_q <= 1'b0; par_bad <= 1'b0; nb_q <= 2'd3;
    end else begin
      rx_valid   <= 1'b0;
      frame_err  <= 1'b0;
      parity_err <= 1'b0;
      case (state)
        IDLE: if (!rx_s) begin
          tcnt <= '0; state <= START;
          par_en_q <= parity_en; par_odd_q <= parity_odd; par_bad <= 1'b0;
          nb_q  <= data_bits;
          shreg <= '0;                     // bits not shifted in stay 0 (keeps parity and alignment clean)
        end
        START: if (tick16) begin           // middle of the start bit
          if (tcnt == 7) begin
            tcnt <= '0; bit_idx <= '0;
            state <= rx_s ? IDLE : DATA;   // glitch -> abort
          end else tcnt <= tcnt + 1'b1;
        end
        DATA: if (tick16) begin            // sample every 16 ticks
          if (tcnt == 15) begin
            tcnt  <= '0;
            shreg <= {rx_s, shreg[7:1]};   // LSB first
            if (bit_idx == 3'd4 + nb_q) state <= par_en_q ? PARITY : STOP;
            else bit_idx <= bit_idx + 1'b1;
          end else tcnt <= tcnt + 1'b1;
        end
        PARITY: if (tick16) begin
          if (tcnt == 15) begin
            tcnt    <= '0;
            par_bad <= rx_s ^ (^shreg) ^ par_odd_q;   // data + parity bit must match the mode
            state   <= STOP;
          end else tcnt <= tcnt + 1'b1;
        end
        STOP: if (tick16) begin
          if (tcnt == 15) begin
            tcnt <= '0;
            // Report both errors independently; data is only valid if neither occurred
            frame_err  <= !rx_s;
            parity_err <= par_bad;
            // Bits arrive at the top of shreg; shift down so the data is right-aligned
            if (rx_s && !par_bad) begin rx_data <= shreg >> (2'd3 - nb_q); rx_valid <= 1'b1; end
            state <= rx_s ? IDLE : WAIT_HIGH;
          end else tcnt <= tcnt + 1'b1;
        end
        WAIT_HIGH: if (rx_s) state <= IDLE; // don't restart until the line is idle
        default: state <= IDLE;
      endcase
    end
  end
endmodule
