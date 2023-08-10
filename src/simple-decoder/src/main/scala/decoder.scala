// -*- coding: utf-8 -*-
// @Time    : 2023/7/9 下午9:46
// @Author  : SuYang
// @File    :
// @Software: IntelliJ IDEA
// @Comment :

import spinal.core._
import spinal.core.internals.Literal
import spinal.lib._

import java.io.{BufferedWriter, File, FileWriter}
import scala.collection.mutable
import scala.collection.mutable.ArrayBuffer
import scala.language.postfixOps

class decoder extends Component {
  val io = new Bundle {
    val inst_i = in Bits(Config.bitWidth bits)
    val fetch_err_i = in Bool()
    val is_o = out Bits()
  }

  if (Config.useJson) {
    JsonInstSet.loadInstructs()
  } else {
    LoongArch32.loadInstructs()
  }
  private val signals = (decoder.encodings.flatMap(_._2.map(_._1)) ++ decoder.defaults.keys).toList.distinct

  // 获取信号名
  private def getSignalName(s: Signal[_ <: BaseType]): String = {
    s.getClass.getSimpleName.replace("$", "").toLowerCase
  }
  // 生成解码器的头文件
  private def genDecoderHeader(): Unit = {
    val file = new File(Config.targetDirectory + "/decoder.svh")
    val bw = new BufferedWriter(new FileWriter(file))
    bw.write("`ifndef _DECODER_SVH_\n")
    bw.write("`define _DECODER_SVH_\n\n")

    bw.write(Config.constPatch + "\n\n")

    // 生成信号对应的结构体
    signals.foreach(s => {
      if (s.dataType.getBitsWidth - 1 > 0) {
        bw.write(s"typedef logic [${s.dataType.getBitsWidth - 1}:0] ${getSignalName(s)}_t;\n")
      } else {
        bw.write(s"typedef logic ${getSignalName(s)}_t;\n")
      }
    })
    bw.write(s"typedef logic [${Config.bitWidth - 1}:0] debug_inst_t;\n\n")

    if (Config.useJson) {
      JsonInstSet.genMacro(bw)
      JsonInstSetLoader.loadInfo()
      Config.stages.foreach(stage => {
            bw.write("typedef struct packed {\n")
            if (Config.debug) bw.write(s"    debug_inst_t debug_inst;\n")
            signals.reverse.foreach(s => {
              // 判断信号使用阶段是否在这个阶段之后
              if (Config.stages.indexOf(JsonInstSetLoader.signals(getSignalName(s))("stage")) >= Config.stages.indexOf(stage)) {
                bw.write(s"    ${getSignalName(s)}_t ${getSignalName(s)};\n")
              }
            })
            bw.write(s"} ${stage}_t;\n\n")
      })
    } else {
      LoongArch32.genMacro(bw)
    }

    bw.write("typedef struct packed {\n")
    if (Config.debug) bw.write(s"    debug_inst_t debug_inst;\n")
    signals.reverse.foreach(s => bw.write(s"    ${getSignalName(s)}_t ${getSignalName(s)};\n"))
    bw.write("} decoder_info_t;\n\n")

    // 生成接线函数
    if (Config.useJson) {
      var preStage = "decoder_info"
      Config.stages.foreach(stage => {
        bw.write(s"function ${stage}_t get_${stage}_from_$preStage(${preStage}_t $preStage);\n")
        bw.write(s"    ${stage}_t ret;\n")
        if (Config.debug) {
          bw.write(s"    ret.debug_inst = $preStage.debug_inst;\n")
        }
        signals.foreach(s => {
          if (Config.stages.indexOf(JsonInstSetLoader.signals(getSignalName(s))("stage")) > Config.stages.indexOf(preStage)) {
            bw.write(s"    ret.${getSignalName(s)} = ${preStage}.${getSignalName(s)};\n")
          }
        })
        bw.write("    return ret;\n")
        bw.write("endfunction\n\n")
        preStage = stage
      })
    }

    bw.write("`endif\n")
    bw.close()
  }
  genDecoderHeader()

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
    decoder.defaults.get(e) match {
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
  private val spec = decoder.encodings.map { case (key, values) =>
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

  spec.foreach(e => println(e._1.toString(32) + "    " + e._2.toString(66)))

  private val decodedBitsWidth = signals.foldLeft(0)(_ + _.dataType.getBitsWidth)
  private def simplify(): Seq[Seq[Masked]] = {
    for (bitId <- 0 until decodedBitsWidth) yield {
      val trueTerm = spec.filter { case (_, t) => t.care.testBit(bitId) && t.value.testBit(bitId) }.keys
      val falseTerm = spec.filter { case (_, t) => t.care.testBit(bitId) && !t.value.testBit(bitId) }.keys
      Simplify.getPrimeImplicitsByTrueAndFalse(trueTerm.toSeq, falseTerm.toSeq, Config.bitWidth)
    }
  }

  private val simplifiedSpec = simplify()

  simplifiedSpec.foreach(e => println(e.map(_.toString(32)).mkString(" ")))

  if (Config.debug) {
    io.is_o := io.inst_i ## simplifiedSpec.map(_.map(_ === io.inst_i).asBits.orR).asBits
  } else {
    io.is_o := simplifiedSpec.map(_.map(_ === io.inst_i).asBits.orR).asBits
  }
  // 接口不输出io前缀
  noIoPrefix()
}

object decoder {
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
//    SpinalSystemVerilog(new Decoder)
    SpinalConfig(targetDirectory = Config.targetDirectory).generateSystemVerilog(new decoder)
  }
}
