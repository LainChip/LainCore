// -*- coding: utf-8 -*-
// @Time    : 2023/7/9 下午9:46
// @Author  : SuYang
// @File    :
// @Software: IntelliJ IDEA
// @Comment :

import spinal.core._
import spinal.core.internals.Literal
import spinal.lib._

import scala.collection.mutable
import scala.collection.mutable.ArrayBuffer
import scala.language.postfixOps

class Decoder extends Component {
  val io = new Bundle {
    val inst = in Bits(32 bits)
    val ctrl = out Bits()
  }

  LoongArch32.loadInstructions()
  private val signals = (Decoder.encodings.flatMap(_._2.map(_._1)) ++ Decoder.defaults.keys).toList.distinct

  private var offset = 0
  private var defaultValue, defaultCare = BigInt(0)
  private val offsetOf = mutable.LinkedHashMap[Signal[_ <: BaseType], Int]()

  private def fixEncoding(e: Signal[_ <: BaseType], value: BaseType): Unit = {
    value.head.source match {
      // 值是一个枚举类型
      case literal: EnumLiteral[_] => literal.fixEncoding(e.dataType.asInstanceOf[SpinalEnumCraft[_]].getEncoding)
      case _ =>
    }
  }

  //Build defaults value and field offset map
  signals.foreach(e => {
    Decoder.defaults.get(e) match {
      case Some(value) => // 如果default有这个值
        fixEncoding(e, value)
        defaultValue += value.head.source.asInstanceOf[Literal].getValue << offset
        defaultCare += ((BigInt(1) << e.dataType.getBitsWidth) - 1) << offset
      case _ =>
    }
    offsetOf(e) = offset
    offset += e.dataType.getBitsWidth
  })

  // 生成解码表
  private val spec = Decoder.encodings.map { case (key, values) =>
    var decodedValue = defaultValue
    var decodedCare = defaultCare
    for ((e, literal) <- values) {
      fixEncoding(e, literal)
      val offset = offsetOf(e)
      decodedValue |= literal.head.source.asInstanceOf[Literal].getValue << offset
      decodedCare |= ((BigInt(1) << e.dataType.getBitsWidth) - 1) << offset
    }
    (Masked(key.value, key.careAbout), Masked(decodedValue, decodedCare))
  }

  private val decodedBitsWidth = signals.foldLeft(0)(_ + _.dataType.getBitsWidth)
  private def simplify(): Seq[Seq[Masked]] = {
    for (bitId <- 0 until decodedBitsWidth) yield {
      val trueTerm = spec.filter { case (_, t) => t.care.testBit(bitId) && t.value.testBit(bitId) }.keys
      val falseTerm = spec.filter { case (_, t) => t.care.testBit(bitId) && !t.value.testBit(bitId) }.keys
      Simplify.getPrimeImplicitsByTrueAndFalse(trueTerm.toSeq, falseTerm.toSeq, 32)
    }
  }

  private val simplifiedSpec = simplify()

  io.ctrl := simplifiedSpec.map(_.map(_ === io.inst).asBits.orR).asBits
}

object Decoder {
  private val defaults = mutable.LinkedHashMap[Signal[_ <: BaseType], BaseType]()
  private val encodings = mutable.LinkedHashMap[MaskedLiteral, ArrayBuffer[(Signal[_ <: BaseType], BaseType)]]()

  def addDefault(key: Signal[_ <: BaseType], value: Any): Unit = {
    assert(!defaults.contains(key))
    defaults(key) = value match {
      case e: SpinalEnumElement[_] => e()
      case e: BaseType => e
    }
  }

  def add(key: MaskedLiteral, values: Seq[(Signal[_ <: BaseType], Any)]): Unit = {
    val instructionModel = encodings.getOrElseUpdate(key, ArrayBuffer[(Signal[_ <: BaseType], BaseType)]())
    values.map { case (a, b) =>
      val value = b match {
        case e: SpinalEnumElement[_] => e()
        case e: BaseType => e
      }
      instructionModel += (a -> value)
    }
  }

  def main(args: Array[String]): Unit = {
    SpinalSystemVerilog(new Decoder)
  }
}
