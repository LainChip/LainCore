module tests_random_stall #(parameter int PERCETAGE = 50) (
  input  logic clk    ,
  input  logic rst_n  ,
  output logic stall_o
);

    `ifdef _FPGA
  assign stall_o = '0;
    `endif

    `ifdef _DIFFTEST_ENABLE
  always_ff @(posedge clk) begin
    stall_o <= (($random() % 100) < PERCETAGE);
  end
    `endif
endmodule