/*--JSON--{"module_name":"mycpu_top","module_ver":"2","module_type":"module"}--JSON--*/

module mycpu_mega_top(
    input           aclk,
    input           aresetn,
    output          global_reset,
    input    [ 7:0] ext_int, 
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

    /*(*mark_debug = "true"*)*/output [31:0] debug_wb_pc,
    /*(*mark_debug = "true"*)*/output [31:0] debug_wb_rf_wdata,
    /*(*mark_debug = "true"*)*/output [31:0] debug_wb_instr
);

    assign global_reset = ~aresetn;
    /*(*mark_debug = "true"*)*/wire[4:0] debug0_wb_rf_wnum_nc;
    /*(*mark_debug = "true"*)*/wire[3:0] debug0_wb_rf_wen_nc;
    core_top #(1'b1) core_wrap(
        .aclk(aclk),
        .aresetn(aresetn),
        .intrpt(ext_int),
        .arid(arid),
        .araddr(araddr),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),
        .arlock(arlock),
        .arcache(arcache),
        .arprot(arprot),
        .arvalid(arvalid),
        .arready(arready),
        .rid(rid),
        .rdata(rdata),
        .rresp(rresp),
        .rlast(rlast),
        .rvalid(rvalid),
        .rready(rready),
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awlock(awlock),
        .awcache(awcache),
        .awprot(awprot),
        .awvalid(awvalid),
        .awready(awready),
        .wid(wid),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),
        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),
        .debug0_wb_pc(debug_wb_pc),
        .debug0_wb_rf_wen(debug0_wb_rf_wen_nc),
        .debug0_wb_rf_wnum(debug0_wb_rf_wnum_nc),
        .debug0_wb_rf_wdata(debug_wb_rf_wdata),
        .debug0_wb_inst(debug_wb_instr)
    );

endmodule
