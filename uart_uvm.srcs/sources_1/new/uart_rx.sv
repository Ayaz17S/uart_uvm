module uart_rx (
  input  logic       clk, rst_n, tick16,
  input  logic       rx_in,
  output logic [7:0] rx_data,
  output logic       rx_valid,
  output logic       frame_err
);
  typedef enum logic [2:0] {IDLE, START, DATA, STOP, WAIT_HIGH} state_t;
  state_t     state;
  logic [3:0] tcnt;
  logic [2:0] bit_idx;
  logic [7:0] shreg;
  logic       rx_s1, rx_s;   // 2-FF synchronizer

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rx_s1 <= 1'b1; rx_s <= 1'b1; end
    else        begin rx_s1 <= rx_in; rx_s <= rx_s1; end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE; tcnt <= '0; bit_idx <= '0; shreg <= '0;
      rx_data <= '0; rx_valid <= 1'b0; frame_err <= 1'b0;
    end else begin
      rx_valid  <= 1'b0;
      frame_err <= 1'b0;
      case (state)
        IDLE: if (!rx_s) begin tcnt <= '0; state <= START; end
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
            if (bit_idx == 7) state <= STOP;
            else bit_idx <= bit_idx + 1'b1;
          end else tcnt <= tcnt + 1'b1;
        end
        STOP: if (tick16) begin
          if (tcnt == 15) begin
            tcnt <= '0;
            if (rx_s) begin rx_data <= shreg; rx_valid <= 1'b1; state <= IDLE; end
            else      begin frame_err <= 1'b1; state <= WAIT_HIGH; end
          end else tcnt <= tcnt + 1'b1;
        end
        WAIT_HIGH: if (rx_s) state <= IDLE; // don't restart until the line is idle
        default: state <= IDLE;
      endcase
    end
  end
endmodule