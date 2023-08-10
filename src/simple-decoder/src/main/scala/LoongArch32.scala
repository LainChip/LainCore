// -*- coding: utf-8 -*-
// @Time    : 2023/7/9 下午9:46
// @Author  : SuYang
// @File    : 
// @Software: IntelliJ IDEA 
// @Comment :
import spinal.core._

import java.io.{BufferedWriter, File, FileWriter}
import scala.language.postfixOps

object LoongArch32 extends InstSet {
  def JIRL = M"010011--------------------------"

  def B = M"010100--------------------------"

  def BL = M"010101--------------------------"

  def BEQ = M"010110--------------------------"

  def BNE = M"010111--------------------------"

  def BLT = M"011000--------------------------"

  def BGE = M"011001--------------------------"

  def BLTU = M"011010--------------------------"

  def BGEU = M"011011--------------------------"


  object BranchCtrlEnum extends SpinalEnum(binarySequential) {
    val INVALID, IMMEDIATE, INDIRECT, CONDITION = newElement()
  }

  object BRANCH_CTRL extends Signal(BranchCtrlEnum())


  override def loadInstructs(): Unit = {
    // add signal default value
    decoder.addDefault(BRANCH_CTRL, BranchCtrlEnum.INVALID)
    // add inst and signal
    decoder.add(JIRL, List(BRANCH_CTRL -> BranchCtrlEnum.INDIRECT))
    decoder.add(B, List(BRANCH_CTRL -> BranchCtrlEnum.IMMEDIATE))
    decoder.add(BL, List(BRANCH_CTRL -> BranchCtrlEnum.IMMEDIATE))
    decoder.add(BEQ, List(BRANCH_CTRL -> BranchCtrlEnum.CONDITION))
    decoder.add(BNE, List(BRANCH_CTRL -> BranchCtrlEnum.CONDITION))
    decoder.add(BLT, List(BRANCH_CTRL -> BranchCtrlEnum.CONDITION))
    decoder.add(BGE, List(BRANCH_CTRL -> BranchCtrlEnum.CONDITION))
    decoder.add(BLTU, List(BRANCH_CTRL -> BranchCtrlEnum.CONDITION))
    decoder.add(BGEU, List(BRANCH_CTRL -> BranchCtrlEnum.CONDITION))

  }

  override def genMacro(bw: BufferedWriter): Unit = {

  }
}