module skid_buf #(
    parameter DATA_LEN = 32
  )(
    input logic clk,
    input logic rst_n,

    input logic[DATA_LEN - 1 : 0] d_i,
    output logic[DATA_LEN - 1 : 0] d_o,

    // FRONT HANDSHAKING
    input logic valid_i,
    output logic ready_o,

    // BACK HANDSHAKING
    output logic valid_o,
    input logic ready_i
  );

  logic skid_q,skid;
  logic[DATA_LEN - 1 : 0] d_q;

  // skid Handling
  always_ff@(posedge clk) begin
    if(~rst_n) begin
      skid_q <= '0;
    end
    else begin
      skid_q <= skid;
    end
  end
  always_comb begin
    if(skid_q) begin
        if(ready_i) begin
            skid = '0;
        end
    end else begin
        if(!ready_i && valid_i) begin
            skid = '1;
        end
    end
  end

  // data Handling
  always_ff@(posedge clk) begin
    if(!skid_q) begin
        d_q <= d_i;
    end
  end

  // ready_o 处理
  assign ready_o = !skid_q;

  // valid_o 处理
  assign valid_o = skid_q | valid_i;

  // d_o 处理
  assign d_o = skid_q ? d_q : d_i;

endmodule
