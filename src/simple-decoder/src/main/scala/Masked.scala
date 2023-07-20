// -*- coding: utf-8 -*-
// @Time    : 2023/7/9 下午9:46
// @Author  : SuYang
// @File    :
// @Software: IntelliJ IDEA
// @Comment :
import spinal.core._

case class Masked(value: BigInt, care: BigInt){
  assert((value & ~care) == 0)
  var isPrime = true // 标记是否为主要蕴含项

  def < (that: Masked): Boolean = value < that.value || value == that.value && ~care < ~that.care

  def intersects(x: Masked): Boolean = ((value ^ x.value) & care & x.care) == 0

  def covers(x: Masked): Boolean = ((value ^ x.value) & care | (~x.care) & care) == 0

  def setPrime(value : Boolean): Masked = {
    isPrime = value
    this
  }

  def mergeOneBitDifSmaller(x: Masked): Masked = {
    val bit = value - x.value
    val ret = new Masked(value &~ bit, care & ~bit)
    isPrime = false
    x.isPrime = false
    ret
  }

  def isSimilarOneBitDifSmaller(x: Masked): Boolean = {
    val diff = value - x.value
    care == x.care && value > x.value && (diff & diff - 1) == 0
  }


  def === (hard : Bits) : Bool = (hard & care) === (value & care)

  def toString(bitCount : Int): String = (0 until bitCount).map(i => if(care.testBit(i)) (if(value.testBit(i)) "1" else "0") else "-").reverseIterator.reduce(_+_)
}
