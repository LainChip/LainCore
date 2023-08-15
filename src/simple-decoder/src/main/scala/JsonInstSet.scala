
import spinal.core._

import java.io.{BufferedWriter, File, FileWriter}
import scala.language.postfixOps

object JsonInstSet extends InstSet {
  // 定义指令opcode
  private def LD_W = M"0010100010----------------------"
  private def INVTLB = M"00000110010010011---------------"
  private def LD_HU = M"0010101001----------------------"
  private def SLLI_W = M"00000000010000001---------------"
  private def SUB_W = M"00000000000100010---------------"
  private def ADD_W = M"00000000000100000---------------"
  private def RDCNT_W = M"0000000000000000011000----------"
  private def BREAK = M"00000000001010100---------------"
  private def MOD_WU = M"00000000001000011---------------"
  private def BGE = M"011001--------------------------"
  private def SRL_W = M"00000000000101111---------------"
  private def SC_W = M"00100001------------------------"
  private def ERTN = M"0000011001001000001110----------"
  private def SLL_W = M"00000000000101110---------------"
  private def BLTU = M"011010--------------------------"
  private def JIRL = M"010011--------------------------"
  private def TLBFILL = M"0000011001001000001101----------"
  private def BGEU = M"011011--------------------------"
  private def RDCNTH_W = M"0000000000000000011001----------"
  private def MULH_WU = M"00000000000111010---------------"
  private def NOR = M"00000000000101000---------------"
  private def ANDI = M"0000001101----------------------"
  private def PRELD_NOP = M"0010101011----------------------"
  private def TLBRD = M"0000011001001000001011----------"
  private def OR = M"00000000000101010---------------"
  private def ST_H = M"0010100101----------------------"
  private def SLTI = M"0000001000----------------------"
  private def MULH_W = M"00000000000111001---------------"
  private def BLT = M"011000--------------------------"
  private def ST_B = M"0010100100----------------------"
  private def MUL_W = M"00000000000111000---------------"
  private def ORI = M"0000001110----------------------"
  private def LU12I_W = M"0001010-------------------------"
  private def IBAR = M"00111000011100101---------------"
  private def XORI = M"0000001111----------------------"
  private def DBAR = M"00111000011100100---------------"
  private def LD_H = M"0010100001----------------------"
  private def B = M"010100--------------------------"
  private def CSRWRXCHG = M"00000100------------------------"
  private def TLBWR = M"0000011001001000001100----------"
  private def XOR = M"00000000000101011---------------"
  private def DIV_W = M"00000000001000000---------------"
  private def CACOP = M"0000011000----------------------"
  private def PCADDU12I = M"0001110-------------------------"
  private def BL = M"010101--------------------------"
  private def SLT = M"00000000000100100---------------"
  private def SLTUI = M"0000001001----------------------"
  private def SRAI_W = M"00000000010010001---------------"
  private def SRA_W = M"00000000000110000---------------"
  private def SRLI_W = M"00000000010001001---------------"
  private def MOD_W = M"00000000001000001---------------"
  private def SYSCALL = M"00000000001010110---------------"
  private def IDLE = M"00000110010010001---------------"
  private def LL_W = M"00100000------------------------"
  private def TLBSRCH = M"0000011001001000001010----------"
  private def BEQ = M"010110--------------------------"
  private def ST_W = M"0010100110----------------------"
  private def ADDI_W = M"0000001010----------------------"
  private def BNE = M"010111--------------------------"
  private def SLTU = M"00000000000100101---------------"
  private def LD_BU = M"0010101000----------------------"
  private def AND = M"00000000000101001---------------"
  private def LD_B = M"0010100000----------------------"
  private def DIV_WU = M"00000000001000010---------------"

  // 定义信号值
  private object AluGrandOpEnum extends SpinalEnum {
    val _ALU_GTYPE_BW = newElement("_ALU_GTYPE_BW")
    val _ALU_GTYPE_MUL = newElement("_ALU_GTYPE_MUL")
    val _ALU_GTYPE_LI = newElement("_ALU_GTYPE_LI")
    val _ALU_GTYPE_INT = newElement("_ALU_GTYPE_INT")
    val _ALU_GTYPE_CMP = newElement("_ALU_GTYPE_CMP")
    val _ALU_GTYPE_SFT = newElement("_ALU_GTYPE_SFT")
    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      _ALU_GTYPE_BW -> 0,
      _ALU_GTYPE_MUL -> 3,
      _ALU_GTYPE_LI -> 1,
      _ALU_GTYPE_INT -> 1,
      _ALU_GTYPE_CMP -> 3,
      _ALU_GTYPE_SFT -> 2
      )
  }
  private object RegTypeWEnum extends SpinalEnum(binarySequential) {
    val _REG_W_NONE = newElement("_REG_W_NONE")
    val _REG_W_RD = newElement("_REG_W_RD")
    val _REG_W_RJD = newElement("_REG_W_RJD")
    val _REG_W_BL1 = newElement("_REG_W_BL1")
  }

  private object MemTypeEnum extends SpinalEnum {
    val _MEM_TYPE_WORD = newElement("_MEM_TYPE_WORD")
    val _MEM_TYPE_HALF = newElement("_MEM_TYPE_HALF")
    val _MEM_TYPE_UWORD = newElement("_MEM_TYPE_UWORD")
    val _MEM_TYPE_UBYTE = newElement("_MEM_TYPE_UBYTE")
    val _MEM_TYPE_NONE = newElement("_MEM_TYPE_NONE")
    val _MEM_TYPE_UHALF = newElement("_MEM_TYPE_UHALF")
    val _MEM_TYPE_BYTE = newElement("_MEM_TYPE_BYTE")
    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      _MEM_TYPE_WORD -> 1,
      _MEM_TYPE_HALF -> 2,
      _MEM_TYPE_UWORD -> 5,
      _MEM_TYPE_UBYTE -> 7,
      _MEM_TYPE_NONE -> 0,
      _MEM_TYPE_UHALF -> 6,
      _MEM_TYPE_BYTE -> 3
      )
  }
  private object ImmTypeEnum extends SpinalEnum {
    val _IMM_S16 = newElement("_IMM_S16")
    val _IMM_U5 = newElement("_IMM_U5")
    val _IMM_U12 = newElement("_IMM_U12")
    val _IMM_S21 = newElement("_IMM_S21")
    val _IMM_S20 = newElement("_IMM_S20")
    val _IMM_S12 = newElement("_IMM_S12")
    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      _IMM_S16 -> 3,
      _IMM_U5 -> 0,
      _IMM_U12 -> 0,
      _IMM_S21 -> 4,
      _IMM_S20 -> 2,
      _IMM_S12 -> 1
      )
  }
  private object AluOpEnum extends SpinalEnum {
    val _ALU_STYPE_LUI = newElement("_ALU_STYPE_LUI")
    val _ALU_STYPE_SLL = newElement("_ALU_STYPE_SLL")
    val _ALU_STYPE_LIEMPTYSLOT = newElement("_ALU_STYPE_LIEMPTYSLOT")
    val _ALU_STYPE_INTEMPTYSLOT1 = newElement("_ALU_STYPE_INTEMPTYSLOT1")
    val _ALU_STYPE_SUB = newElement("_ALU_STYPE_SUB")
    val _DIV_TYPE_MOD = newElement("_DIV_TYPE_MOD")
    val _ALU_STYPE_PCPLUS4 = newElement("_ALU_STYPE_PCPLUS4")
    val _ALU_STYPE_NOR = newElement("_ALU_STYPE_NOR")
    val _DIV_TYPE_DIVU = newElement("_DIV_TYPE_DIVU")
    val _ALU_STYPE_INTEMPTYSLOT0 = newElement("_ALU_STYPE_INTEMPTYSLOT0")
    val _MUL_TYPE_MULHU = newElement("_MUL_TYPE_MULHU")
    val _ALU_STYPE_AND = newElement("_ALU_STYPE_AND")
    val _MUL_TYPE_MULL = newElement("_MUL_TYPE_MULL")
    val _ALU_STYPE_PCADDUI = newElement("_ALU_STYPE_PCADDUI")
    val _ALU_STYPE_XOR = newElement("_ALU_STYPE_XOR")
    val _ALU_STYPE_SLT = newElement("_ALU_STYPE_SLT")
    val _ALU_STYPE_SRA = newElement("_ALU_STYPE_SRA")
    val _DIV_TYPE_DIV = newElement("_DIV_TYPE_DIV")
    val _ALU_STYPE_OR = newElement("_ALU_STYPE_OR")
    val _ALU_STYPE_SRL = newElement("_ALU_STYPE_SRL")
    val _DIV_TYPE_MODU = newElement("_DIV_TYPE_MODU")
    val _ALU_STYPE_SLTU = newElement("_ALU_STYPE_SLTU")
    val _MUL_TYPE_MULH = newElement("_MUL_TYPE_MULH")
    val _ALU_STYPE_ADD = newElement("_ALU_STYPE_ADD")
    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      _ALU_STYPE_LUI -> 1,
      _ALU_STYPE_SLL -> 2,
      _ALU_STYPE_LIEMPTYSLOT -> 0,
      _ALU_STYPE_INTEMPTYSLOT1 -> 2,
      _ALU_STYPE_SUB -> 2,
      _DIV_TYPE_MOD -> 2,
      _ALU_STYPE_PCPLUS4 -> 2,
      _ALU_STYPE_NOR -> 0,
      _DIV_TYPE_DIVU -> 1,
      _ALU_STYPE_INTEMPTYSLOT0 -> 0,
      _MUL_TYPE_MULHU -> 2,
      _ALU_STYPE_AND -> 1,
      _MUL_TYPE_MULL -> 0,
      _ALU_STYPE_PCADDUI -> 3,
      _ALU_STYPE_XOR -> 3,
      _ALU_STYPE_SLT -> 0,
      _ALU_STYPE_SRA -> 0,
      _DIV_TYPE_DIV -> 0,
      _ALU_STYPE_OR -> 2,
      _ALU_STYPE_SRL -> 3,
      _DIV_TYPE_MODU -> 3,
      _ALU_STYPE_SLTU -> 1,
      _MUL_TYPE_MULH -> 1,
      _ALU_STYPE_ADD -> 0
      )
  }
  private object FuSelExEnum extends SpinalEnum(binarySequential) {
    val _FUSEL_EX_NONE = newElement("_FUSEL_EX_NONE")
    val _FUSEL_EX_ALU = newElement("_FUSEL_EX_ALU")
  }

  private object FuSelWbEnum extends SpinalEnum(binarySequential) {
    val _FUSEL_WB_NONE = newElement("_FUSEL_WB_NONE")
    val _FUSEL_WB_DIV = newElement("_FUSEL_WB_DIV")
  }

  private object FuSelM2Enum extends SpinalEnum(binarySequential) {
    val _FUSEL_M2_NONE = newElement("_FUSEL_M2_NONE")
    val _FUSEL_M2_ALU = newElement("_FUSEL_M2_ALU")
    val _FUSEL_M2_CSR = newElement("_FUSEL_M2_CSR")
    val _FUSEL_M2_MEM = newElement("_FUSEL_M2_MEM")
  }

  private object CsrRdcntEnum extends SpinalEnum(binarySequential) {
    val _RDCNT_NONE = newElement("_RDCNT_NONE")
    val _RDCNT_ID_VLOW = newElement("_RDCNT_ID_VLOW")
    val _RDCNT_VHIGH = newElement("_RDCNT_VHIGH")
    val _RDCNT_VLOW = newElement("_RDCNT_VLOW")
  }

  private object TargetTypeEnum extends SpinalEnum(binarySequential) {
    val _TARGET_REL = newElement("_TARGET_REL")
    val _TARGET_ABS = newElement("_TARGET_ABS")
  }

  private object RegTypeR0Enum extends SpinalEnum(binarySequential) {
    val _REG_R0_NONE = newElement("_REG_R0_NONE")
    val _REG_R0_RK = newElement("_REG_R0_RK")
    val _REG_R0_RD = newElement("_REG_R0_RD")
    val _REG_R0_IMM = newElement("_REG_R0_IMM")
  }

  private object FuSelM1Enum extends SpinalEnum(binarySequential) {
    val _FUSEL_M1_NONE = newElement("_FUSEL_M1_NONE")
    val _FUSEL_M1_ALU = newElement("_FUSEL_M1_ALU")
    val _FUSEL_M1_MEM = newElement("_FUSEL_M1_MEM")
  }

  private object RegTypeR1Enum extends SpinalEnum(binarySequential) {
    val _REG_R1_NONE = newElement("_REG_R1_NONE")
    val _REG_R1_RJ = newElement("_REG_R1_RJ")
  }

  private object AddrImmTypeEnum extends SpinalEnum(binarySequential) {
    val _ADDR_IMM_S26 = newElement("_ADDR_IMM_S26")
    val _ADDR_IMM_S12 = newElement("_ADDR_IMM_S12")
    val _ADDR_IMM_S14 = newElement("_ADDR_IMM_S14")
    val _ADDR_IMM_S16 = newElement("_ADDR_IMM_S16")
  }

  private object CmpTypeEnum extends SpinalEnum {
    val _CMP_LTU = newElement("_CMP_LTU")
    val _CMP_NONE = newElement("_CMP_NONE")
    val _CMP_LE = newElement("_CMP_LE")
    val _CMP_E = newElement("_CMP_E")
    val _CMP_NOCONDITION = newElement("_CMP_NOCONDITION")
    val _CMP_NE = newElement("_CMP_NE")
    val _CMP_GT = newElement("_CMP_GT")
    val _CMP_GE = newElement("_CMP_GE")
    val _CMP_LT = newElement("_CMP_LT")
    val _CMP_GEU = newElement("_CMP_GEU")
    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      _CMP_LTU -> 8,
      _CMP_NONE -> 0,
      _CMP_LE -> 13,
      _CMP_E -> 4,
      _CMP_NOCONDITION -> 14,
      _CMP_NE -> 10,
      _CMP_GT -> 3,
      _CMP_GE -> 7,
      _CMP_LT -> 9,
      _CMP_GEU -> 6
      )
  }
  // 定义信号
  private object ALU_GRAND_OP extends Signal(AluGrandOpEnum())

  private object MEM_CACOP extends Signal(Bool())

  private object CSR_OP_EN extends Signal(Bool())

  private object NEED_CSR extends Signal(Bool())

  private object REG_TYPE_W extends Signal(RegTypeWEnum())

  private object NEED_MUL extends Signal(Bool())

  private object MEM_TYPE extends Signal(MemTypeEnum())

  private object LATEST_RFALSE_EX extends Signal(Bool())

  private object IMM_TYPE extends Signal(ImmTypeEnum())

  private object LATEST_R0_M2 extends Signal(Bool())

  private object ALU_OP extends Signal(AluOpEnum())

  private object LATEST_R0_EX extends Signal(Bool())

  private object MEM_READ extends Signal(Bool())

  private object LATEST_R1_M2 extends Signal(Bool())

  private object NEED_DIV extends Signal(Bool())

  private object IBARRIER extends Signal(Bool())

  private object FU_SEL_EX extends Signal(FuSelExEnum())

  private object TLBFILL_EN extends Signal(Bool())

  private object BREAK_INST extends Signal(Bool())

  private object FU_SEL_WB extends Signal(FuSelWbEnum())

  private object FU_SEL_M2 extends Signal(FuSelM2Enum())

  private object WAIT_INST extends Signal(Bool())

  private object TLBWR_EN extends Signal(Bool())

  private object CSR_RDCNT extends Signal(CsrRdcntEnum())

  private object MEM_WRITE extends Signal(Bool())

  private object INVTLB_EN extends Signal(Bool())

  private object NEED_BPU extends Signal(Bool())

  private object LATEST_R1_M1 extends Signal(Bool())

  private object NEED_LSU extends Signal(Bool())

  private object ERTN_INST extends Signal(Bool())

  private object SYSCALL_INST extends Signal(Bool())

  private object TLBRD_EN extends Signal(Bool())

  private object TARGET_TYPE extends Signal(TargetTypeEnum())

  private object REG_TYPE_R0 extends Signal(RegTypeR0Enum())

  private object LATEST_R1_EX extends Signal(Bool())

  private object FU_SEL_M1 extends Signal(FuSelM1Enum())

  private object REG_TYPE_R1 extends Signal(RegTypeR1Enum())

  private object DBARRIER extends Signal(Bool())

  private object LLSC_INST extends Signal(Bool())

  private object LATEST_R0_WB extends Signal(Bool())

  private object PRIV_INST extends Signal(Bool())

  private object TLBSRCH_EN extends Signal(Bool())

  private object LATEST_RFALSE_M1 extends Signal(Bool())

  private object ADDR_IMM_TYPE extends Signal(AddrImmTypeEnum())

  private object LATEST_R1_WB extends Signal(Bool())

  private object CMP_TYPE extends Signal(CmpTypeEnum())

  private object LATEST_R0_M1 extends Signal(Bool())

  private object REFETCH extends Signal(Bool())

  // 加载指令解码信息
  override def loadInstructs(): Unit = {
    // add signal default value
    decoder.addDefault(ALU_GRAND_OP, AluGrandOpEnum._ALU_GTYPE_BW)
    decoder.addDefault(MEM_CACOP, False)
    decoder.addDefault(CSR_OP_EN, False)
    decoder.addDefault(NEED_CSR, False)
    decoder.addDefault(REG_TYPE_W, RegTypeWEnum._REG_W_NONE)
    decoder.addDefault(NEED_MUL, False)
    decoder.addDefault(MEM_TYPE, MemTypeEnum._MEM_TYPE_NONE)
    decoder.addDefault(LATEST_RFALSE_EX, False)
    decoder.addDefault(IMM_TYPE, ImmTypeEnum._IMM_U5)
    decoder.addDefault(LATEST_R0_M2, False)
    decoder.addDefault(ALU_OP, AluOpEnum._ALU_STYPE_NOR)
    decoder.addDefault(LATEST_R0_EX, False)
    decoder.addDefault(MEM_READ, False)
    decoder.addDefault(LATEST_R1_M2, False)
    decoder.addDefault(NEED_DIV, False)
    decoder.addDefault(IBARRIER, False)
    decoder.addDefault(FU_SEL_EX, FuSelExEnum._FUSEL_EX_NONE)
    decoder.addDefault(TLBFILL_EN, False)
    decoder.addDefault(BREAK_INST, False)
    decoder.addDefault(FU_SEL_WB, FuSelWbEnum._FUSEL_WB_NONE)
    decoder.addDefault(FU_SEL_M2, FuSelM2Enum._FUSEL_M2_NONE)
    decoder.addDefault(WAIT_INST, False)
    decoder.addDefault(TLBWR_EN, False)
    decoder.addDefault(CSR_RDCNT, CsrRdcntEnum._RDCNT_NONE)
    decoder.addDefault(MEM_WRITE, False)
    decoder.addDefault(INVTLB_EN, False)
    decoder.addDefault(NEED_BPU, False)
    decoder.addDefault(LATEST_R1_M1, False)
    decoder.addDefault(NEED_LSU, False)
    decoder.addDefault(ERTN_INST, False)
    decoder.addDefault(SYSCALL_INST, False)
    decoder.addDefault(TLBRD_EN, False)
    decoder.addDefault(TARGET_TYPE, TargetTypeEnum._TARGET_REL)
    decoder.addDefault(REG_TYPE_R0, RegTypeR0Enum._REG_R0_NONE)
    decoder.addDefault(LATEST_R1_EX, False)
    decoder.addDefault(FU_SEL_M1, FuSelM1Enum._FUSEL_M1_NONE)
    decoder.addDefault(REG_TYPE_R1, RegTypeR1Enum._REG_R1_NONE)
    decoder.addDefault(DBARRIER, False)
    decoder.addDefault(LLSC_INST, False)
    decoder.addDefault(LATEST_R0_WB, False)
    decoder.addDefault(PRIV_INST, False)
    decoder.addDefault(TLBSRCH_EN, False)
    decoder.addDefault(LATEST_RFALSE_M1, False)
    decoder.addDefault(ADDR_IMM_TYPE, AddrImmTypeEnum._ADDR_IMM_S26)
    decoder.addDefault(LATEST_R1_WB, False)
    decoder.addDefault(CMP_TYPE, CmpTypeEnum._CMP_NONE)
    decoder.addDefault(LATEST_R0_M1, False)
    decoder.addDefault(REFETCH, False)
    // add inst and signal
    decoder.add(LD_W, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_WORD,
      MEM_READ -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_MEM,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(INVTLB, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      LATEST_R0_M2 -> True,
      LATEST_R1_M2 -> True,
      CSR_RDCNT -> CsrRdcntEnum._RDCNT_ID_VLOW,
      INVTLB_EN -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      REFETCH -> True
    ))
    decoder.add(LD_HU, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_UHALF,
      MEM_READ -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(SLLI_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_SFT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_U5,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_SLL,
      LATEST_R1_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(SUB_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_INT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      ALU_OP -> AluOpEnum._ALU_STYPE_SUB,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(ADD_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_INT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      ALU_OP -> AluOpEnum._ALU_STYPE_ADD,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(RDCNT_W, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RJD,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_CSR,
      CSR_RDCNT -> CsrRdcntEnum._RDCNT_ID_VLOW,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26
    ))
    decoder.add(BREAK, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      BREAK_INST -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26
    ))
    decoder.add(MOD_WU, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._DIV_TYPE_MODU,
      LATEST_R1_M2 -> True,
      NEED_DIV -> True,
      FU_SEL_WB -> FuSelWbEnum._FUSEL_WB_DIV,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(BGE, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      NEED_BPU -> True,
      LATEST_R1_M1 -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_GE,
      LATEST_R0_M1 -> True
    ))
    decoder.add(SRL_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_SFT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_SRL,
      LATEST_R1_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(SC_W, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_WORD,
      LATEST_R0_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      MEM_WRITE -> True,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LLSC_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S14
    ))
    decoder.add(ERTN, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      ERTN_INST -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26
    ))
    decoder.add(SLL_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_SFT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_SLL,
      LATEST_R1_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(BLTU, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      NEED_BPU -> True,
      LATEST_R1_M1 -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_LTU,
      LATEST_R0_M1 -> True
    ))
    decoder.add(JIRL, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_LI,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      ALU_OP -> AluOpEnum._ALU_STYPE_PCPLUS4,
      LATEST_R0_EX -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      NEED_BPU -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_ABS,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_NOCONDITION
    ))
    decoder.add(TLBFILL, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      TLBFILL_EN -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      REFETCH -> True
    ))
    decoder.add(BGEU, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      NEED_BPU -> True,
      LATEST_R1_M1 -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_GEU,
      LATEST_R0_M1 -> True
    ))
    decoder.add(RDCNTH_W, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RJD,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_CSR,
      CSR_RDCNT -> CsrRdcntEnum._RDCNT_VHIGH,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26
    ))
    decoder.add(MULH_WU, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_MUL,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      NEED_MUL -> True,
      ALU_OP -> AluOpEnum._MUL_TYPE_MULHU,
      LATEST_R0_EX -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(NOR, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_NOR,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(ANDI, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_U12,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_AND,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(PRELD_NOP, List())
    decoder.add(TLBRD, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      TLBRD_EN -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      REFETCH -> True
    ))
    decoder.add(OR, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_OR,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(ST_H, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_HALF,
      LATEST_R0_M2 -> True,
      MEM_WRITE -> True,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(SLTI, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_CMP,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_S12,
      ALU_OP -> AluOpEnum._ALU_STYPE_SLT,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(MULH_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_MUL,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      NEED_MUL -> True,
      ALU_OP -> AluOpEnum._MUL_TYPE_MULH,
      LATEST_R0_EX -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(BLT, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      NEED_BPU -> True,
      LATEST_R1_M1 -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_LT,
      LATEST_R0_M1 -> True
    ))
    decoder.add(ST_B, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_BYTE,
      LATEST_R0_M2 -> True,
      MEM_WRITE -> True,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(MUL_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_MUL,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      NEED_MUL -> True,
      ALU_OP -> AluOpEnum._MUL_TYPE_MULL,
      LATEST_R0_EX -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(ORI, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_U12,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_OR,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(LU12I_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_LI,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_S20,
      ALU_OP -> AluOpEnum._ALU_STYPE_LUI,
      LATEST_R0_EX -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE
    ))
    decoder.add(IBAR, List(
      IBARRIER -> True,
      REFETCH -> True,
      NEED_CSR -> True
    ))
    decoder.add(XORI, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_U12,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_XOR,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(DBAR, List(
      DBARRIER -> True,
      REFETCH -> True,
      NEED_CSR -> True
    ))
    decoder.add(LD_H, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_HALF,
      MEM_READ -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(B, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      LATEST_R0_EX -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      NEED_BPU -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      CMP_TYPE -> CmpTypeEnum._CMP_NOCONDITION
    ))
    decoder.add(CSRWRXCHG, List(
      CSR_OP_EN -> True,
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_CSR,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      LATEST_R0_M1 -> True,
      REFETCH -> True
    ))
    decoder.add(TLBWR, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      TLBWR_EN -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      REFETCH -> True
    ))
    decoder.add(XOR, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_XOR,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(DIV_W, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._DIV_TYPE_DIV,
      LATEST_R1_M2 -> True,
      NEED_DIV -> True,
      FU_SEL_WB -> FuSelWbEnum._FUSEL_WB_DIV,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(CACOP, List(
      MEM_CACOP -> True,
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_BYTE,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12,
      REFETCH -> True
    ))
    decoder.add(PCADDU12I, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_LI,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_S20,
      ALU_OP -> AluOpEnum._ALU_STYPE_PCADDUI,
      LATEST_R0_EX -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE
    ))
    decoder.add(BL, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_LI,
      REG_TYPE_W -> RegTypeWEnum._REG_W_BL1,
      ALU_OP -> AluOpEnum._ALU_STYPE_PCPLUS4,
      LATEST_R0_EX -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      NEED_BPU -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      CMP_TYPE -> CmpTypeEnum._CMP_NOCONDITION
    ))
    decoder.add(SLT, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_CMP,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      ALU_OP -> AluOpEnum._ALU_STYPE_SLT,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(SLTUI, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_CMP,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_S12,
      ALU_OP -> AluOpEnum._ALU_STYPE_SLTU,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(SRAI_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_SFT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_U5,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_SRA,
      LATEST_R1_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(SRA_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_SFT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_SRA,
      LATEST_R1_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(SRLI_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_SFT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_U5,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_SRL,
      LATEST_R1_M2 -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(MOD_W, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._DIV_TYPE_MOD,
      LATEST_R1_M2 -> True,
      NEED_DIV -> True,
      FU_SEL_WB -> FuSelWbEnum._FUSEL_WB_DIV,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(SYSCALL, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      SYSCALL_INST -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26
    ))
    decoder.add(IDLE, List(
      NEED_CSR -> True,
      WAIT_INST -> True,
      PRIV_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      REFETCH -> True
    ))
    decoder.add(LL_W, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_WORD,
      MEM_READ -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LLSC_INST -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S14
    ))
    decoder.add(TLBSRCH, List(
      NEED_CSR -> True,
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_NONE,
      PRIV_INST -> True,
      TLBSRCH_EN -> True,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S26,
      REFETCH -> True
    ))
    decoder.add(BEQ, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      NEED_BPU -> True,
      LATEST_R1_M1 -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_E,
      LATEST_R0_M1 -> True
    ))
    decoder.add(ST_W, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_WORD,
      LATEST_R0_M2 -> True,
      MEM_WRITE -> True,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(ADDI_W, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_INT,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      IMM_TYPE -> ImmTypeEnum._IMM_S12,
      ALU_OP -> AluOpEnum._ALU_STYPE_ADD,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_IMM,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(BNE, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_NONE,
      NEED_BPU -> True,
      LATEST_R1_M1 -> True,
      TARGET_TYPE -> TargetTypeEnum._TARGET_REL,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RD,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S16,
      CMP_TYPE -> CmpTypeEnum._CMP_NE,
      LATEST_R0_M1 -> True
    ))
    decoder.add(SLTU, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_CMP,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      ALU_OP -> AluOpEnum._ALU_STYPE_SLTU,
      LATEST_R1_M1 -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      LATEST_R0_M1 -> True
    ))
    decoder.add(LD_BU, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_UBYTE,
      MEM_READ -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(AND, List(
      ALU_GRAND_OP -> AluGrandOpEnum._ALU_GTYPE_BW,
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._ALU_STYPE_AND,
      LATEST_R1_M2 -> True,
      FU_SEL_EX -> FuSelExEnum._FUSEL_EX_ALU,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_ALU,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      FU_SEL_M1 -> FuSelM1Enum._FUSEL_M1_ALU,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
    decoder.add(LD_B, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      MEM_TYPE -> MemTypeEnum._MEM_TYPE_BYTE,
      MEM_READ -> True,
      FU_SEL_M2 -> FuSelM2Enum._FUSEL_M2_MEM,
      NEED_LSU -> True,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_NONE,
      LATEST_R1_EX -> True,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ,
      ADDR_IMM_TYPE -> AddrImmTypeEnum._ADDR_IMM_S12
    ))
    decoder.add(DIV_WU, List(
      REG_TYPE_W -> RegTypeWEnum._REG_W_RD,
      LATEST_R0_M2 -> True,
      ALU_OP -> AluOpEnum._DIV_TYPE_DIVU,
      LATEST_R1_M2 -> True,
      NEED_DIV -> True,
      FU_SEL_WB -> FuSelWbEnum._FUSEL_WB_DIV,
      REG_TYPE_R0 -> RegTypeR0Enum._REG_R0_RK,
      REG_TYPE_R1 -> RegTypeR1Enum._REG_R1_RJ
    ))
  }

  // 生成宏定义
  override def genMacro(bw: BufferedWriter): Unit = {
    def minWidth(value: Int): Int = {
      val numBits = if (value >= 0) {
        if (value == 0) 1
        else scala.math.ceil(scala.math.log(value + 1) / scala.math.log(2)).toInt
      } else {
        if (value == -1) 1
        else scala.math.ceil(scala.math.log(-value) / scala.math.log(2)).toInt + 1
      }
      //    println(s"The minimum width for representing $value is $numBits bits.")
      numBits
    }

    def getWidth(enum: SpinalEnum): Int = {
      val values = enum.elements.map(e => enum.defaultEncoding.getValue(e))
      val max = values.max.toInt
      val min = values.min.toInt
      val width = scala.math.max(minWidth(max), minWidth(min))
      //    println(s"The width of the enum is $width bits.")
      width
    }

    AluGrandOpEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(AluGrandOpEnum)}'d${AluGrandOpEnum.defaultEncoding.getValue(e)})\n") }
    RegTypeWEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(RegTypeWEnum)}'d${RegTypeWEnum.defaultEncoding.getValue(e)})\n") }
    MemTypeEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(MemTypeEnum)}'d${MemTypeEnum.defaultEncoding.getValue(e)})\n") }
    ImmTypeEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(ImmTypeEnum)}'d${ImmTypeEnum.defaultEncoding.getValue(e)})\n") }
    AluOpEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(AluOpEnum)}'d${AluOpEnum.defaultEncoding.getValue(e)})\n") }
    FuSelExEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(FuSelExEnum)}'d${FuSelExEnum.defaultEncoding.getValue(e)})\n") }
    FuSelWbEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(FuSelWbEnum)}'d${FuSelWbEnum.defaultEncoding.getValue(e)})\n") }
    FuSelM2Enum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(FuSelM2Enum)}'d${FuSelM2Enum.defaultEncoding.getValue(e)})\n") }
    CsrRdcntEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(CsrRdcntEnum)}'d${CsrRdcntEnum.defaultEncoding.getValue(e)})\n") }
    TargetTypeEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(TargetTypeEnum)}'d${TargetTypeEnum.defaultEncoding.getValue(e)})\n") }
    RegTypeR0Enum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(RegTypeR0Enum)}'d${RegTypeR0Enum.defaultEncoding.getValue(e)})\n") }
    FuSelM1Enum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(FuSelM1Enum)}'d${FuSelM1Enum.defaultEncoding.getValue(e)})\n") }
    RegTypeR1Enum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(RegTypeR1Enum)}'d${RegTypeR1Enum.defaultEncoding.getValue(e)})\n") }
    AddrImmTypeEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(AddrImmTypeEnum)}'d${AddrImmTypeEnum.defaultEncoding.getValue(e)})\n") }
    CmpTypeEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(CmpTypeEnum)}'d${CmpTypeEnum.defaultEncoding.getValue(e)})\n") }
    bw.write("\n")
  }
}
