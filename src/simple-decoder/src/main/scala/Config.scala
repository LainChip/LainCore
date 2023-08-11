// -*- coding: utf-8 -*-
// @Time    : 2023/8/9 下午6:50
// @Author  : SuYang
// @File    : Config
// @Software: IntelliJ IDEA 
// @Comment :

object Config {
  val useJson = true
  val stages: List[String] = List("is", "ex", "m1", "m2", "wb")
  // 如果有想要添加到decoder.svh的其他和解码无关常量
  val constPatch: String =
    """
      |`define _LINK_TYPE_PCPLUS4 (2'b00)
      |`define _CSR_CRMD (14'h0)
      |`define _CSR_PRMD (14'h1)
      |`define _CSR_EUEN (14'h2)
      |`define _CSR_ECTL (14'h4)
      |`define _CSR_ESTAT (14'h5)
      |`define _CSR_ERA (14'h6)
      |`define _CSR_BADV (14'h7)
      |`define _CSR_EENTRY (14'hc)
      |`define _CSR_TLBIDX (14'h10)
      |`define _CSR_TLBEHI (14'h11)
      |`define _CSR_TLBELO0 (14'h12)
      |`define _CSR_TLBELO1 (14'h13)
      |`define _CSR_ASID (14'h18)
      |`define _CSR_PGDL (14'h19)
      |`define _CSR_PGDH (14'h1a)
      |`define _CSR_PGD (14'h1b)
      |`define _CSR_CPUID (14'h20)
      |`define _CSR_SAVE0 (14'h30)
      |`define _CSR_SAVE1 (14'h31)
      |`define _CSR_SAVE2 (14'h32)
      |`define _CSR_SAVE3 (14'h33)
      |`define _CSR_TID (14'h40)
      |`define _CSR_TCFG (14'h41)
      |`define _CSR_TVAL (14'h42)
      |`define _CSR_CNTC (14'h43)
      |`define _CSR_TICLR (14'h44)
      |`define _CSR_LLBCTL (14'h60)
      |`define _CSR_TLBRENTRY (14'h88)
      |`define _CSR_CTAG (14'h98)
      |`define _CSR_DMW0 (14'h180)
      |`define _CSR_DMW1 (14'h181)
      |`define _CSR_BRK (14'h100)
      |`define _CSR_DISABLE_CACHE (14'h101)
      |`define _INV_TLB_ALL (4'b1111)
      |`define _INV_TLB_MASK_G (4'b1000)
      |`define _INV_TLB_MASK_NG (4'b0100)
      |`define _INV_TLB_MASK_ASID (4'b0010)
      |`define _INV_TLB_MASK_VA (4'b0001)
      |""".stripMargin

  val debug = true
  val checkInvalidInst = true
  val exceptionStage = "m1"
  val bitWidth = 32
  val targetDirectory = "rtl" /*"/home/suyang/chiplab/IP/myCPU"*/
  val defaultInstSet: InstSet = LoongArch32
}
