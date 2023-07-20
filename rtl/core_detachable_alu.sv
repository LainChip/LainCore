`include "decoder.svh"

module core_detachable_alu #(
    parameter bit USE_LI = 0,
    parameter bit USE_INT = 1,
    parameter bit USE_MUL = 0,
    parameter bit USE_SFT = 1,
    parameter bit USE_CMP = 1
  )(
    input   logic [31:0] mul_i,
    input   logic [31:0] r0_i,
    input   logic [31:0] r1_i,
    input   logic [31:0] pc_i,
    input   logic [1:0] grand_op_i,
    input   logic [1:0] op_i,

    output  logic [31:0] res_o
  );
  logic [31:0] g0_result, g1_result, g2_result, g3_result;
  // BW : definitely exist
  if((USE_LI || USE_INT || USE_MUL) && (USE_SFT || USE_CMP)) begin
    // FULL 4 - 1
    always_comb begin
      case(op_i)
        default: /*00*/
        begin
          res_o = g0_result;
        end
        `_ALU_GTYPE_INT: begin
          res_o = g1_result;
        end
        `_ALU_GTYPE_SFT: begin
          res_o = g2_result;
        end
        `_ALU_GTYPE_CMP: begin
          res_o = g3_result;
        end
      endcase
    end
  end

  if((USE_LI || USE_INT || USE_MUL) && !(USE_SFT || USE_CMP)) begin
    // ONLY 2 - 1
    always_comb begin
      case(op_i[0])
        default: /*0*/
        begin
          res_o = g0_result;
        end
        1'b1: begin
          res_o = g1_result;
        end
      endcase
    end
  end

  if(!(USE_LI || USE_INT || USE_MUL) && (USE_SFT || USE_CMP)) begin
    // ONLY 2 - 1 | 3 - 1
    always_comb begin
      case(op_i[1])
        default: /*0*/
        begin
          res_o = g0_result;
        end
        1'b1: begin
          if(USE_SFT & !USE_CMP) begin
            res_o = g2_result;
          end
          else if(!USE_SFT & USE_CMP) begin
            res_o = g3_result;
          end
          else begin
            res_o = op_i[0] ? g3_result : g2_result;
          end
        end
      endcase
    end
  end

  if(!(USE_LI || USE_INT || USE_MUL) && !(USE_SFT || USE_CMP)) begin
    assign res_o = g0_result;
  end

  if(USE_LI) begin
    always_comb begin
      case (op_i)
        `_ALU_STYPE_NOR: begin
          g0_result = ~(r1_i | r0_i);
        end
        `_ALU_STYPE_AND: begin
          g0_result = r1_i & r0_i;
        end
        `_ALU_STYPE_OR: begin
          g0_result = r1_i | r0_i;
        end
        `_ALU_STYPE_XOR: begin
          g0_result = r1_i ^ r0_i;
        end
      endcase
    end
  end


  if(USE_INT) begin
    always_comb begin
      case (op_i[1])
        default: begin // 2'b00
          g1_result = r1_i + r0_i;
        end
        1'b1: begin // 2'b10
          g1_result = r1_i - r0_i;
        end
      endcase
    end
  end
  else if(USE_LI) begin
    always_comb begin
      case (op_i)
        default: begin  // 2'b01 == `_ALU_STYPE_LUI
          g1_result = {r0_i[19:0], 12'd0};
        end
        `_ALU_STYPE_PCPLUS4: begin  // 2'b10
          g1_result = 32'd4 + pc_i;
        end
        `_ALU_STYPE_PCADDUI: begin  // 2'b11
          g1_result = r0_i + pc_i;
        end
      endcase
    end
  end
  else if(USE_MUL) begin
    always_comb begin
      g1_result = mul_i;
    end
  end
  else begin
    assign g1_result = '0;
  end

  if (USE_SFT) begin
    // SFT
    always_comb begin
      case (op_i)
        default/* `_ALU_STYPE_SLL */: begin
          g2_result = r1_i << r0_i[4:0];
        end
        `_ALU_STYPE_SRL: begin
          g2_result = r1_i >> r0_i[4:0];
        end
        `_ALU_STYPE_SRA: begin
          g2_result = $signed($signed(r1_i) >>> $signed(r0_i[4:0]));
        end
      endcase
    end
  end
  else begin
    assign g2_result = '0;
  end

  if (USE_CMP) begin
    // CMP
    logic ext;
    logic[32:0] r0,r1;
    assign r0[31:0] = r0_i;
    assign r1[31:0] = r1_i;
    assign r0[32] = r0_i[31] & ext;
    assign r1[32] = r1_i[31] & ext;
    assign ext = op_i[0]; // JUDGE SLT
    assign g3_result[31:1] = '0;
    assign g3_result[0] = r1 < r0;
  end
  else begin
    assign g3_result = '0;
  end


endmodule
