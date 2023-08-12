`include "lsu_types.svh"

module bus_mux_2x1 #(
    parameter int CACHE_PORT_NUM = 2
  )(
    input wire clk,
    input wire rst_n,

    input  cache_bus_req_t  [CACHE_PORT_NUM-1:0] req_i, // cache的访问请求
    output cache_bus_resp_t [CACHE_PORT_NUM-1:0] resp_o, // cache的访问应答
    LA_AXI_BUS.Master   mem_bus // 作为master，向核外访存
  );

  LA_AXI_BUS ibus;
  LA_AXI_BUS dbus;

  axi_converter #(
                  .CACHE_PORT_NUM(1)
                ) ibus_converter_0 (
                  .clk(clk),
                  .rst_n(rst_n),
                  .axi_bus_if(ibus),
                  .req_i(req_i[0]),
                  .resp_o(resp_o[0])
                );

  axi_converter #(
                  .CACHE_PORT_NUM(1)
                ) dbus_converter_1 (
                  .clk(clk),
                  .rst_n(rst_n),
                  .axi_bus_if(dbus),
                  .req_i(req_i[1]),
                  .resp_o(resp_o[1])
                );

  // TOOD: multiple combinational drivers warning, why?
  logic [3:0] aw_len_wasted, ar_len_wasted; 
  logic [2:0] aw_qos_wasted, ar_qos_wasted;
  logic [1:0] b_resp_wasted, r_resp_wasted;

  la_axixbar # (
            .C_AXI_DATA_WIDTH(32),
            .C_AXI_ADDR_WIDTH(32),
            .C_AXI_ID_WIDTH(4), // TODO: should it also add log2(NM)? 
            .NM(2),
            .NS(1),
            .SLAVE_ADDR(32'b0),
            .SLAVE_MASK(32'b0), // TODO: check

            .OPT_LOWPOWER(0),
            .OPT_LINGER(4), // TODO: check
            .OPT_QOS(0),
            .LGMAXBURST(3)  // TODO: check
          ) axi_crossbar_2x1 (
            .S_AXI_ACLK   (clk),
            .S_AXI_ARESETN(rst_n),
            // slave
            .S_AXI_AWID   ({dbus.aw_id, ibus.aw_id}),
            .S_AXI_AWADDR ({dbus.aw_addr, ibus.aw_addr}),
            .S_AXI_AWLEN  ({4'b0, dbus.aw_len, 4'b0, ibus.aw_len}), // TODO: check, width unmatch
            .S_AXI_AWSIZE ({dbus.aw_size, ibus.aw_size}),
            .S_AXI_AWBURST({dbus.aw_burst, ibus.aw_burst}),
            .S_AXI_AWLOCK ({dbus.aw_lock, ibus.aw_lock}),
            .S_AXI_AWCACHE({dbus.aw_cache, ibus.aw_cache}),
            .S_AXI_AWPROT ({dbus.aw_prot, ibus.aw_prot}),
            .S_AXI_AWQOS  ({3'b0, dbus.aw_qos, 3'b0, ibus.aw_qos}),
            .S_AXI_AWVALID({dbus.aw_valid, ibus.aw_valid}),
            .S_AXI_AWREADY({dbus.aw_ready, ibus.aw_ready}),
            .S_AXI_WDATA  ({dbus.w_data, ibus.w_data}),
            .S_AXI_WSTRB  ({dbus.w_strb, ibus.w_strb}),
            .S_AXI_WLAST  ({dbus.w_last, ibus.w_last}),
            .S_AXI_WVALID ({dbus.w_valid, ibus.w_valid}),
            .S_AXI_WREADY ({dbus.w_ready, ibus.w_ready}),
            .S_AXI_BID    ({dbus.b_id, ibus.b_id}),
            .S_AXI_BRESP  ({b_resp_wasted[1], dbus.b_resp, b_resp_wasted[0], ibus.b_resp}),
            .S_AXI_BVALID ({dbus.b_valid, ibus.b_valid}),
            .S_AXI_BREADY ({dbus.b_ready, ibus.b_ready}),
            .S_AXI_ARID   ({dbus.ar_id, ibus.ar_id}),
            .S_AXI_ARADDR ({dbus.ar_addr, ibus.ar_addr}),
            .S_AXI_ARLEN  ({4'b0, dbus.ar_len, 4'b0, ibus.ar_len}),
            .S_AXI_ARSIZE ({dbus.ar_size, ibus.ar_size}),
            .S_AXI_ARBURST({dbus.ar_burst, ibus.ar_burst}),
            .S_AXI_ARLOCK ({dbus.ar_lock, ibus.ar_lock}),
            .S_AXI_ARCACHE({dbus.ar_cache, ibus.ar_cache}),
            .S_AXI_ARPROT ({dbus.ar_prot, ibus.ar_prot}),
            .S_AXI_ARQOS  ({3'b0, dbus.ar_qos, 3'b0, ibus.ar_qos}),
            .S_AXI_ARVALID({dbus.ar_valid, ibus.ar_valid}),
            .S_AXI_ARREADY({dbus.ar_ready, ibus.ar_ready}),
            .S_AXI_RID    ({dbus.r_id, ibus.r_id}),
            .S_AXI_RDATA  ({dbus.r_data, ibus.r_data}),
            .S_AXI_RRESP  ({r_resp_wasted[1], dbus.r_resp, r_resp_wasted[0], ibus.r_resp}),
            .S_AXI_RLAST  ({dbus.r_last, ibus.r_last}),
            .S_AXI_RVALID ({dbus.r_valid, ibus.r_valid}),
            .S_AXI_RREADY ({dbus.r_ready, ibus.r_ready}),

            // master
            .M_AXI_AWID   (mem_bus.aw_id),
            .M_AXI_AWADDR (mem_bus.aw_addr),
            .M_AXI_AWLEN  ({aw_len_wasted, mem_bus.aw_len}),
            .M_AXI_AWSIZE ({mem_bus.aw_size}),
            .M_AXI_AWBURST({mem_bus.aw_burst}),
            .M_AXI_AWLOCK ({mem_bus.aw_lock}),
            .M_AXI_AWCACHE({mem_bus.aw_cache}),
            .M_AXI_AWPROT ({mem_bus.aw_prot}),
            .M_AXI_AWQOS  ({aw_qos_wasted, mem_bus.aw_qos}),
            .M_AXI_AWVALID({mem_bus.aw_valid}),
            .M_AXI_AWREADY({mem_bus.aw_ready}),
            .M_AXI_WDATA  ({mem_bus.w_data}),
            .M_AXI_WSTRB  ({mem_bus.w_strb}),
            .M_AXI_WLAST  ({mem_bus.w_last}),
            .M_AXI_WVALID ({mem_bus.w_valid}),
            .M_AXI_WREADY ({mem_bus.w_ready}),
            .M_AXI_BID    ({mem_bus.b_id}),
            .M_AXI_BRESP  ({1'b0, mem_bus.b_resp}),
            .M_AXI_BVALID ({mem_bus.b_valid}),
            .M_AXI_BREADY ({mem_bus.b_ready}),
            .M_AXI_ARID   ({mem_bus.ar_id}),
            .M_AXI_ARADDR ({mem_bus.ar_addr}),
            .M_AXI_ARLEN  ({ar_len_wasted, mem_bus.ar_len}),
            .M_AXI_ARSIZE ({mem_bus.ar_size}),
            .M_AXI_ARBURST({mem_bus.ar_burst}),
            .M_AXI_ARLOCK ({mem_bus.ar_lock}),
            .M_AXI_ARCACHE({mem_bus.ar_cache}),
            .M_AXI_ARQOS  ({ar_qos_wasted, mem_bus.ar_qos}),
            .M_AXI_ARPROT ({mem_bus.ar_prot}),
            .M_AXI_ARVALID({mem_bus.ar_valid}),
            .M_AXI_ARREADY({mem_bus.ar_ready}),
            .M_AXI_RID    ({mem_bus.r_id}),
            .M_AXI_RDATA  ({mem_bus.r_data}),
            .M_AXI_RRESP  ({1'b0, mem_bus.r_resp}),
            .M_AXI_RLAST  ({mem_bus.r_last}),
            .M_AXI_RVALID ({mem_bus.r_valid}),
            .M_AXI_RREADY ({mem_bus.r_ready})
          );


endmodule
