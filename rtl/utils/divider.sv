/*
2023-1-18 v1: xrb完成
*/
module divider (
    input logic clk,
    input logic rst_n,

    /* slave */
    input  logic div_valid,
    output logic div_ready,
    output logic res_valid,
    input  logic res_ready,

    input  logic div_signed_i,
    input  logic [31:0] Z_i,
    input  logic [31:0] D_i,
    output logic [31:0] q_o, s_o
  );

  // for unit test: dump waves for gtkwave
  // `ifndef _DIFFTEST_ENABLED
  //     initial begin
  //     	$dumpfile("logs/vlt_dump.vcd");
  //     	$dumpvars();
  //     end
  // `endif

  /*======= deal with operands' sign =======*/
  logic [31:0] dividend_absZ, divisor_absD;
  logic opp_q, opp_s; // need opposite at last
  /* e.g.
      Z_i   D_i   q_o   s_o
       5  /  3  =  1 ... 2
       5  / -3  = -1 ... 2
      -5  /  3  = -1 ...-2
      -5  / -3  =  1 ...-2
  */
  assign opp_q = (Z_i[31] ^ D_i[31]) & div_signed_i;
  assign opp_s = Z_i[31] & div_signed_i;
  // change to abs() form, change back at the end
  assign dividend_absZ = (div_signed_i & Z_i[31]) ? ~Z_i + 1'b1 : Z_i;
  assign divisor_absD  = (div_signed_i & D_i[31]) ? ~D_i + 1'b1 : D_i;


  /*======= auxiliary signals for divider =======*/
  logic [31:0] timer;

  logic [63:0] abs_A64, abs_64B;
  assign abs_A64 = {32'b0, dividend_absZ};
  assign abs_64B = {divisor_absD,  32'b0};

  logic      [66:0] tmpA;
  logic [2:0][66:0] tmpB, partial_sub;
  for (genvar i = 0; i < 3; i += 1) begin
    assign partial_sub[i] = (tmpA << 2) - tmpB[i];
  end

  /*======= fsm's state of divider =======*/
  localparam S_DIV_IDLE = 0;
  localparam S_DIV_BUSY = 1;
  logic div_status;

  always_ff @(posedge clk) begin : div_fsm
    if (~rst_n) begin
      div_status <= S_DIV_IDLE;
    end
    else begin
      case (div_status)
        S_DIV_IDLE: begin
          if (div_valid & div_ready) begin
            div_status <= S_DIV_BUSY;
          end
        end
        S_DIV_BUSY: begin
          if (res_valid & res_ready) begin
            // slave get result and master can receive
            if (div_valid & div_ready) begin
              div_status <= S_DIV_BUSY;
            end
            else begin
              div_status <= S_DIV_IDLE;
            end
          end
          /* otherwise, status will stall at S_DIV_BUSY.
           * As timer be zero, res_valid should remain high,
           * then div_ready remains low, so timer won't regresh.
           *   ==> waiting for res_ready from master */
        end
        default:
          ;
      endcase
    end
  end

  /* handshake signals are all wires */
  assign div_ready = (div_status == S_DIV_IDLE) | (res_valid & res_ready);
  assign res_valid = (div_status == S_DIV_BUSY) & ~timer[0];

  /*======= divide process, copy from tyh =======*/
  always_ff @(posedge clk) begin : div_process
    if (~rst_n) begin
      timer <= 0;
    end
    else begin
      if (div_valid & div_ready) begin
        timer <= 32'hffff_ffff;
        tmpA  <= {3'b0, abs_A64};
        tmpB[0] <= {3'b0, abs_64B};
        tmpB[1] <= {3'b0, abs_64B} << 1;
        tmpB[2] <= {3'b0, abs_64B} + ({3'b0, abs_64B} << 1);
        // priority: '+' higher than '<<'
      end
      else if (timer[15] & tmpA[47:16] < tmpB[0][63:32]) begin
        timer <= timer >> 16;
        tmpA  <= tmpA << 16;
      end
      else if (timer[7]  & tmpA[55:24] < tmpB[0][63:32]) begin
        timer <= timer >> 8;
        tmpA  <= tmpA << 8;
      end
      else if (timer[3]  & tmpA[59:28] < tmpB[0][63:32]) begin
        timer <= timer >> 4;
        tmpA  <= tmpA << 4;
      end
      else if (timer[0]) begin
        timer <= timer >> 2;
        tmpA  <= (~partial_sub[2][66]) ? partial_sub[2] + 3 :
              (~partial_sub[1][66]) ? partial_sub[1] + 2 :
              (~partial_sub[0][66]) ? partial_sub[0] + 1 :
              tmpA << 2;
      end
    end
  end

  assign q_o = opp_q ? ~tmpA[31: 0] + 1 : tmpA[31: 0];
  assign s_o = opp_s ? ~tmpA[63:32] + 1 : tmpA[63:32];

endmodule
