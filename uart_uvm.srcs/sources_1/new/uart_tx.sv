module uart_tx (
  input  logic       clk, rst_n, tick16,
  input  logic       tx_valid,
  input  logic [7:0] tx_data,
  output logic       tx_ready,
  output logic       tx_out
);
  typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
  state_t     state;
  logic [3:0] tcnt;
  logic [2:0] bit_idx;
  logic [7:0] shreg;

  // Accept only on a tick so every bit is exactly 16 ticks long
  assign tx_ready = (state == IDLE) && tick16;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE; tx_out <= 1'b1; tcnt <= '0; bit_idx <= '0; shreg <= '0;
    end else begin
      case (state)
        IDLE: begin
          tx_out <= 1'b1;
          if (tx_valid && tx_ready) begin
            shreg <= tx_data; tcnt <= '0; tx_out <= 1'b0; state <= START;
          end
        end
        START: if (tick16) begin
          if (tcnt == 15) begin
            tcnt <= '0; bit_idx <= '0;
            tx_out <= shreg[0]; shreg <= {1'b0, shreg[7:1]};
            state <= DATA;
          end else tcnt <= tcnt + 1'b1;
        end
        DATA: if (tick16) begin
          if (tcnt == 15) begin
            tcnt <= '0;
            if (bit_idx == 7) begin tx_out <= 1'b1; state <= STOP; end
            else begin
              bit_idx <= bit_idx + 1'b1;
              tx_out  <= shreg[0]; shreg <= {1'b0, shreg[7:1]};
            end
          end else tcnt <= tcnt + 1'b1;
        end
        STOP: if (tick16) begin
          if (tcnt == 15) begin tcnt <= '0; state <= IDLE; end
          else tcnt <= tcnt + 1'b1;
        end
      endcase
    end
  end
endmodule