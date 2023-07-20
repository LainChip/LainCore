```
        "_REG_TYPE_I": "5'b00_0_00",
        "_REG_TYPE_RW": "5'b00_1_01",
        "_REG_TYPE_RRW": "5'b01_1_01",
        "_REG_TYPE_W": "5'b01_1_01",
        "_REG_TYPE_RR": "5'b10_1_00",
        "_REG_TYPE_BL": "5'b00_0_11",
        "_REG_TYPE_CSRXCHG": "5'b10_1_01",
        "_REG_TYPE_RDCNTID": "5'b00_0_10",
        "_REG_TYPE_INVTLB": "5'b01_1_00",
        "_REG_WB_ALU": "3'd0",
        "_REG_WB_BPF": "3'd1",
        "_REG_WB_LSU": "3'd2",
        "_REG_WB_CSR": "3'd3",
        "_REG_WB_MDU": "3'd4",

        "pipe_one_inst": {
            "length": 1,
            "stage": "is",
            "default_value": "fetch_err_i",
            "invalid_value": "1'b1"
        },
        "pipe_two_inst": {
            "length": 1,
            "stage": "is",
            "default_value": "1'b0",
            "invalid_value": "1'b0"
        },
        "ready_time": {
            "length": 1,
            "stage": "is",
            "default_value": "`_READY_M2",
            "invalid_value": "`_READY_EX"
        },
        "use_time": {
            "length": 2,
            "stage": "is",
            "default_value": "{`_USE_EX,`_USE_EX}",
            "invalid_value": "{`_USE_EX,`_USE_EX}"
        },


        "_ALU_TYPE_NIL" : "4'd0",
        "_ALU_TYPE_ADD" : "4'd1", //int
        "_ALU_TYPE_SUB" : "4'd2", //int
        "_ALU_TYPE_SLT" : "4'd3",  //CMP + -
        "_ALU_TYPE_AND" : "4'd4", //BW
        "_ALU_TYPE_OR"  : "4'd5", //BW
        "_ALU_TYPE_XOR" : "4'd6", //BW
        "_ALU_TYPE_NOR" : "4'd7", //BW
        "_ALU_TYPE_SL"  : "4'd8",
        "_ALU_TYPE_SR"  : "4'd9",
        "_ALU_TYPE_MUL" : "4'd10",
        "_ALU_TYPE_MULH": "4'd11",
        "_ALU_TYPE_DIV" : "4'd12",
        "_ALU_TYPE_MOD" : "4'd13",
        "_ALU_TYPE_LUI" : "4'd14", //int

```