// -*- coding: utf-8 -*-
// @Time    : 2023/8/9 下午3:10
// @Author  : SuYang
// @File    : TestSpinalEumu
// @Software: IntelliJ IDEA 
// @Comment :

import spinal.core._
import spinal.lib._

class TestSpinalEnum extends Component {
  object MyEnumStatic extends SpinalEnum {
    val e0, e1, e2, e3 = newElement()
    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      e0 -> 0,
      e1 -> 2,
      e2 -> 3,
      e3 -> 7)
  }

  MyEnumStatic.elements.foreach{e => println(e + " : " + MyEnumStatic.defaultEncoding.getValue(e))}

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
    println(s"The width of the enum is $width bits.")
    width
  }

  println(getWidth(MyEnumStatic))



}

object TestSpinalEnum {
  def main(args: Array[String]): Unit = {
    SpinalSystemVerilog(new TestSpinalEnum)
  }
}
