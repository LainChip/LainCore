`include "common.svh"

module core_top(
  input           aclk,
  input           aresetn,
  input    [ 7:0] intrpt,
  //AXI interface
  //read reqest
  output   [ 3:0] arid,
  output   [31:0] araddr,
  output   [ 7:0] arlen,
  output   [ 2:0] arsize,
  output   [ 1:0] arburst,
  output   [ 1:0] arlock,
  output   [ 3:0] arcache,
  output   [ 2:0] arprot,
  output          arvalid,
  input           arready,
  //read back
  input    [ 3:0] rid,
  input    [31:0] rdata,
  input    [ 1:0] rresp,
  input           rlast,
  input           rvalid,
  output          rready,
  //write request
  output   [ 3:0] awid,
  output   [31:0] awaddr,
  output   [ 7:0] awlen,
  output   [ 2:0] awsize,
  output   [ 1:0] awburst,
  output   [ 1:0] awlock,
  output   [ 3:0] awcache,
  output   [ 2:0] awprot,
  output          awvalid,
  input           awready,
  //write data
  output   [ 3:0] wid,
  output   [31:0] wdata,
  output   [ 3:0] wstrb,
  output          wlast,
  output          wvalid,
  input           wready,
  //write back
  input    [ 3:0] bid,
  input    [ 1:0] bresp,
  input           bvalid,
  output          bready,

`ifdef _DIFFTEST_ENABLE
  input break_point,
  input infor_flag,
  input reg_num,
  input ws_valid,
  input rf_rdata,
`endif
  output [31:0] debug0_wb_pc,
  output [ 3:0] debug0_wb_rf_wen,
  output [ 4:0] debug0_wb_rf_wnum,
  output [31:0] debug0_wb_rf_wdata,
  output [31:0] debug0_wb_inst,
  output [31:0] debug1_wb_pc,
  output [ 3:0] debug1_wb_rf_wen,
  output [ 4:0] debug1_wb_rf_wnum,
  output [31:0] debug1_wb_rf_wdata,
  output [31:0] debug1_wb_inst
);

LA_AXI_BUS mem_bus ();

// assign mem_bus.Slave.aw_ready = awready;
// assign mem_bus.Slave.w_ready = wready;
// assign mem_bus.Slave.b_id = bid;
// assign mem_bus.Slave.b_resp = bresp;
// assign mem_bus.Slave.b_user = '0;
// assign mem_bus.Slave.b_valid = bvalid;
// assign mem_bus.Slave.ar_ready = arready;
// assign mem_bus.Slave.r_id = rid;
// assign mem_bus.Slave.r_data = rdata;
// assign mem_bus.Slave.r_resp = rresp;
// assign mem_bus.Slave.r_last = rlast;
// assign mem_bus.Slave.r_user = '0;
// assign mem_bus.Slave.r_valid = rvalid;

// assign awid = mem_bus.Slave.aw_id;
// assign awaddr = mem_bus.Slave.aw_addr;
// assign awlen = mem_bus.Slave.aw_len;
// assign awsize = mem_bus.Slave.aw_size;
// assign awburst = mem_bus.Slave.aw_burst;
// assign awlock = mem_bus.Slave.aw_lock;
// assign awcache = mem_bus.Slave.aw_cache;
// assign awprot = mem_bus.Slave.aw_prot;
// assign awvalid = mem_bus.Slave.aw_valid;
// assign wdata = mem_bus.Slave.w_data;
// assign wstrb = mem_bus.Slave.w_strb;
// assign wlast = mem_bus.Slave.w_last;
// assign wvalid = mem_bus.Slave.w_valid;
// assign bready = mem_bus.Slave.b_ready;
// assign arid = mem_bus.Slave.ar_id;
// assign araddr = mem_bus.Slave.ar_addr;
// assign arlen = mem_bus.Slave.ar_len;
// assign arsize = mem_bus.Slave.ar_size;
// assign arburst = mem_bus.Slave.ar_burst;
// assign arlock = mem_bus.Slave.ar_lock;
// assign arcache = mem_bus.Slave.ar_cache;
// assign arprot = mem_bus.Slave.ar_prot;
// assign arvalid = mem_bus.Slave.ar_valid;
// assign rready = mem_bus.Slave.r_ready;

assign mem_bus.aw_ready = awready;
assign mem_bus.w_ready  = wready;
assign mem_bus.b_id     = bid;
assign mem_bus.b_resp   = bresp;
assign mem_bus.b_user   = '0;
assign mem_bus.b_valid  = bvalid;
assign mem_bus.ar_ready = arready;
assign mem_bus.r_id     = rid;
assign mem_bus.r_data   = rdata;
assign mem_bus.r_resp   = rresp;
assign mem_bus.r_last   = rlast;
assign mem_bus.r_user   = '0;
assign mem_bus.r_valid  = rvalid;

assign awid    = mem_bus.aw_id;
assign awaddr  = mem_bus.aw_addr;
assign awlen   = {4'b0000,mem_bus.aw_len};
assign awsize  = mem_bus.aw_size;
assign awburst = mem_bus.aw_burst;
assign awlock  = mem_bus.aw_lock;
assign awcache = mem_bus.aw_cache;
assign awprot  = mem_bus.aw_prot;
assign awvalid = mem_bus.aw_valid;
assign wid     = mem_bus.aw_id;
assign wdata   = mem_bus.w_data;
assign wstrb   = mem_bus.w_strb;
assign wlast   = mem_bus.w_last;
assign wvalid  = mem_bus.w_valid;
assign bready  = mem_bus.b_ready;
assign arid    = mem_bus.ar_id;
assign araddr  = mem_bus.ar_addr;
assign arlen   = {4'b0000,mem_bus.ar_len};
assign arsize  = mem_bus.ar_size;
assign arburst = mem_bus.ar_burst;
assign arlock  = mem_bus.ar_lock;
assign arcache = mem_bus.ar_cache;
assign arprot  = mem_bus.ar_prot;
assign arvalid = mem_bus.ar_valid;
assign rready  = mem_bus.r_ready;

logic rst_n;
always_ff @(posedge aclk) begin
  rst_n <= aresetn;
end

core core (
  .clk    (aclk   ),
  .rst_n  (rst_n  ),
  .int_i  (intrpt ),
  .mem_bus(mem_bus)
);

// assign debug0_wb_pc = core.backend.wb_data_flow[0].pc;
// assign debug0_wb_pc = '0;
// assign debug0_wb_rf_wen = '0;
// assign debug0_wb_rf_wnum = '0;
// assign debug0_wb_rf_wdata = '0;
// assign debug0_wb_inst = '0;

endmodule
