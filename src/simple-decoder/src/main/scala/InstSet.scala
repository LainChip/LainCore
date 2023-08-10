// -*- coding: utf-8 -*-
// @Time    : 2023/7/10 下午10:29
// @Author  : SuYang
// @File    : 
// @Software: IntelliJ IDEA 
// @Comment :
import java.io.BufferedWriter
trait InstSet {
  def loadInstructs(): Unit
  // 生成宏
  def genMacro(bw: BufferedWriter): Unit
}
