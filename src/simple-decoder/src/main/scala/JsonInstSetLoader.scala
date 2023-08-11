// -*- coding: utf-8 -*-
// @Time    : 2023/7/18 下午6:25
// @Author  : SuYang
// @File    :
// @Software: IntelliJ IDEA
// @Comment :
import spinal.core.{SpinalError, SpinalInfo, SpinalWarning}

import java.io.{BufferedWriter, File, FileWriter}
import scala.io.Source
import scala.util.parsing.json.JSON

object JsonInstSetLoader {
  private var signalValues: Map[String, _] = Map()
  var instructs: Map[String, Map[String, _]] = Map()
  var signals: Map[String, Map[String, _]] = Map()

  // 检查指令定义的合法性
  private def check(): Unit = {
    // 检查是否存定义了信号但未定义信号取值的情况
    for ((k, _) <- signals) {
      if (!signalValues.contains(k)) {
        SpinalError("Error: signal " + k + " is not defined in signal values")
        System.exit(1)
      }
    }
    // 检查信号的defualt值是否在信号取值范围内
    for ((k, v) <- signals) {
      if (v.contains("default")) {
        val default = v("default")
        signalValues(k) match {
          case values: Map[Any, _] =>
            if (!values.keySet.contains(default)) {
              SpinalError("Error: default value " + default + " of signal " + k + " is not in signal values")
              System.exit(1)
            }
          case values: List[_] =>
            if (!values.contains(default)) {
              SpinalError("Error: default value " + default + " of signal " + k + " is not in signal values")
              System.exit(1)
            }
          case _ =>
        }

      }
    }
    // 检查指令的解码信号是否在信号定义中
    for ((k, v) <- instructs) {
      for ((k1, _) <- v) {
        if (k1 != "opcode" && !signals.contains(k1)) {
          SpinalError("Error: signal " + k1 + " in instruct " + k + " is not defined in signals")
          System.exit(1)
        }
      }
    }

    // 检查指令的解码信号是否在信号取值范围内
    for ((k, v) <- instructs) {
      for ((k1, v1) <- v) {
        if (k1 != "opcode") {
          signalValues(k1) match {
            case values: Map[Any, _] =>
              if (!values.keySet.contains(v1)) {
                SpinalError("Error: value " + v1 + " of signal " + k1 + " in instruct " + k + " is not in signal values")
                System.exit(1)
              }
            case values: List[_] =>
              if (!values.contains(v1)) {
                SpinalError("Error: value " + v1 + " of signal " + k1 + " in instruct " + k + " is not in signal values")
                System.exit(1)
              }
            case _ =>
          }
        }
      }
    }

    // 检查信号的stage是否在stages中
    for ((k, v) <- signals) {
      if (v.contains("stage")) {
        val stage = v("stage")
        if (!Config.stages.contains(stage)) {
          SpinalError("Error: stage " + stage + " of signal " + k + " is not in stages")
          System.exit(1)
        }
      } else {
        SpinalError("Error: stage of signal " + k + " is not defined")
        System.exit(1)
      }
    }

    // 一个信号在所有指令解码信息有定义 & 值全部相同 & 与default不相同，那么警告
    for ((k, v) <- signals) {
      val values = instructs.values.map(_.getOrElse(k, v("default"))).toList
      // 统计信号在解码信息定义中出现的次数
      var count = 0
      instructs.values.foreach{v => if (v.contains(k)) count += 1}
      if (values.distinct.length == 1 && values.head != v("default") && count == instructs.size) {
        SpinalWarning("signal " + k + " is defined in instructs but all values are same and not equal to default")
      }
    }
  }

  // 获取所有解码信息
  def loadInfo(): Unit = {
    val jsonList = getJsonList
    // 从列表中逐个读取json文件
    for (jsonFile <- jsonList) {
      val source = Source.fromFile(jsonFile)
      val lines = try source.mkString finally source.close()
      val json = JSON.parseFull(lines)
      json match {
        case Some(map: Map[String, Any]) =>
          val signalValue = map("signal_values").asInstanceOf[Map[String, _]]
          val instruct = map("instructs").asInstanceOf[Map[String, Map[String, _]]]
          val signal = map("signals").asInstanceOf[Map[String, Map[String, _]]]
          // 将浮点数转为整数后存入
          signalValues ++= signalValue.mapValues {
            case value: Map[Any, _] => value.mapValues {
              case v: Double => v.toInt
              case v => v
            }
            case value => value
          }
          instructs ++= instruct
          signals ++= signal
        case None => SpinalError("Parsing failed")
        case other => SpinalError("Unknown data structure: " + other)
      }
    }
    check()
  }

  // 将下划线命名转为驼峰命名, 如: "alu_op" -> "AluOp"
  private def toCamelCase(str: String): String = {
    val words = str.split("_")
    val camelCase = words.map(_.capitalize).mkString
    camelCase
  }

  private def getJsonList: Array[String] = {
    val dir = new File(".")
    val jsonFiles = dir.listFiles.filter(_.getName.endsWith(".json")).map(_.getName)
    SpinalInfo(Console.BLUE + "Load json files: " + jsonFiles.mkString(", ") + Console.RESET)
    jsonFiles
  }

  // 保留字符串中字母和数字将其他字符替换为下划线
  private def toUnderline(str: String): String = {
    val pattern = "[^a-zA-Z0-9]".r
    pattern.replaceAllIn(str, "_")
  }

  // 判断信号值是否是宏定义
  private def isMacro(values: Any): Boolean = {
    values match {
      case v: List[_] => v.toSet != Set(true, false)
      case _ => false
    }
  }

  // 生成spinalHDL的信号值定义
  private def genSignalValueDefs(): String = {
    val signalDef = new StringBuilder
    for ((k, v) <- signalValues) {
      v match {
        case values: Map[Any, _] =>
          signalDef ++= """  private object %sEnum extends SpinalEnum {
                          |    %s
                          |""".stripMargin.format(toCamelCase(k), values.map(v => s"""val ${v._1.toString} = newElement("${v._1.toString}")""").mkString("\n    "))
          // 利用Map生成初始值
          signalDef ++= """    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
              |      %s
              |      )
              |  }
              |""".stripMargin.format(values.map(x => x._1.toString + " -> " + x._2.toString).mkString(",\n      "))
        case values: List[_] =>
          if (isMacro(values)) {
            signalDef ++= """  private object %sEnum extends SpinalEnum(binarySequential) {
                            |    %s
                            |  }
                            |
                            |""".stripMargin.format(toCamelCase(k), values.map(v => s"""val ${v.toString} = newElement("${v.toString}")""").mkString("\n    "))
          }
        case _ =>
      }
    }
    signalDef.toString()
  }

  // 生成spinalHDL的信号定义
  private def genSignalDefs(): String = {
    val signalDef = new StringBuilder
    for ((k, _) <- signals) {
      signalValues(k) match {
        case _: Map[Any, _] =>
          signalDef ++= """  private object %s extends Signal(%s)
              |
              |""".stripMargin.format(k.toUpperCase(), toCamelCase(k) + "Enum()")
        case values: List[_] =>
            signalDef ++= """  private object %s extends Signal(%s)
                |
                |""".stripMargin.format(k.toUpperCase(), if (isMacro(values)) toCamelCase(k) + "Enum()" else "Bool()")
        case _ =>
      }
    }
    signalDef.toString()
  }

  // 生成spinalHDL的指令Masked形式
  private def genMaskedInstructs(): String = {
    val maskedInstructs = new StringBuilder
    for ((k, v) <- instructs) {
      maskedInstructs ++= "  private def %s = M\"%s\"\n".format(toUnderline(k).toUpperCase, v.apply("opcode") + ("-" * (32 - v.apply("opcode").toString.length)))
    }
    maskedInstructs ++= "\n"
    maskedInstructs.toString()
  }

  // 实现指令解码信息加载函数
  private def loadInstructDecodeInfo(): String = {
    val defaultLoader = new StringBuilder
    val decodeLoader = new StringBuilder
    // 加载默认值
    for ((k, v) <- signals) {
      if (v.contains("default")) {
        signalValues(k) match {
          case _: Map[Any, _] =>
            defaultLoader ++= "    decoder.addDefault(%s, %s)\n".format(k.toUpperCase(), toCamelCase(k) + "Enum." + v.apply("default"))
          case values: List[_] =>
            defaultLoader ++= "    decoder.addDefault(%s, %s)\n".format(k.toUpperCase(), if (isMacro(values)) toCamelCase(k) + "Enum." + v.apply("default") else toCamelCase(v.apply("default").toString))
          case _ =>
        }
      }
    }
    // 加载指令解码信息
    // 去除指令中的opcode字段
    val instructsWithoutOpcode = instructs.map(x => x._1 -> x._2.filter(_._1 != "opcode"))
    for ((k, v) <- instructsWithoutOpcode) {
      if (v.nonEmpty) {
        decodeLoader ++= "    decoder.add(%s, List(\n".format(toUnderline(k).toUpperCase)
        for ((signal, value) <- v) {
          signalValues(signal) match {
            case _: Map[Any, _] =>
              decodeLoader ++= "      %s -> %s,\n".format(signal.toUpperCase(), toCamelCase(signal) + "Enum." + value)
            case values: List[_] =>
              decodeLoader ++= "      %s -> %s,\n".format(signal.toUpperCase(), if (isMacro(values)) toCamelCase(signal) + "Enum." + value else toCamelCase(value.toString))
            case _ =>
          }
        }
        // 删除decodeLoader最后一个逗号
        decodeLoader.deleteCharAt(decodeLoader.length - 2)
        decodeLoader ++= "    ))\n"
      } else {
        decodeLoader ++= "    decoder.add(%s, List())\n".format(toUnderline(k).toUpperCase)
      }
    }
    "  override def loadInstructs(): Unit = {\n" +
       "    // add signal default value\n" + defaultLoader.toString() +
       "    // add inst and signal\n" + decodeLoader.toString() +
       "  }\n\n"
  }

  // 生成信号值宏定义
  private def genMacroDefs(): String = {
    val macroDefs = new StringBuilder
    macroDefs ++= "  override def genMacro(bw: BufferedWriter): Unit = {\n"
    macroDefs ++= """    def minWidth(value: Int): Int = {
                    |      val numBits = if (value >= 0) {
                    |        if (value == 0) 1
                    |        else scala.math.ceil(scala.math.log(value + 1) / scala.math.log(2)).toInt
                    |      } else {
                    |        if (value == -1) 1
                    |        else scala.math.ceil(scala.math.log(-value) / scala.math.log(2)).toInt + 1
                    |      }
                    |      //    println(s"The minimum width for representing $value is $numBits bits.")
                    |      numBits
                    |    }
                    |
                    |    def getWidth(enum: SpinalEnum): Int = {
                    |      val values = enum.elements.map(e => enum.defaultEncoding.getValue(e))
                    |      val max = values.max.toInt
                    |      val min = values.min.toInt
                    |      val width = scala.math.max(minWidth(max), minWidth(min))
                    |      //    println(s"The width of the enum is $width bits.")
                    |      width
                    |    }
                    |
                    |""".stripMargin
    macroDefs ++= s"""${
            val signalDef = new StringBuilder
            for ((k, v) <- signalValues) {
              v match {
                case _: Map[Any, _] =>
                  signalDef ++= """    %sEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(%sEnum)}'d${%sEnum.defaultEncoding.getValue(e)})\n") }""".format(toCamelCase(k), toCamelCase(k), toCamelCase(k))
                  signalDef ++= "\n"
                case values: List[_] =>
                  if (isMacro(values)) {
                    signalDef ++= """    %sEnum.elements.foreach{ e => bw.write(s"`define $e (${getWidth(%sEnum)}'d${%sEnum.defaultEncoding.getValue(e)})\n") }""".format(toCamelCase(k), toCamelCase(k), toCamelCase(k))
                    signalDef ++= "\n"
                  }
                case _ =>
              }
            }
            signalDef.toString()
          }    bw.write("\\n")
          |  }""".stripMargin
    macroDefs.toString()
  }

  // 生成指令集类
  private def genInstSet(): Unit = {
    loadInfo()
    val instSet = new StringBuilder
    instSet ++=
       """
         |import spinal.core._
         |
         |import java.io.{BufferedWriter, File, FileWriter}
         |import scala.language.postfixOps
         |
         |object JsonInstSet extends InstSet {
         |""".stripMargin
    instSet ++= "  // 定义指令opcode\n"
    instSet ++= genMaskedInstructs()
    instSet ++= "  // 定义信号值\n"
    instSet ++= genSignalValueDefs()
    instSet ++= "  // 定义信号\n"
    instSet ++= genSignalDefs()
    instSet ++= "  // 加载指令解码信息\n"
    instSet ++= loadInstructDecodeInfo()
    instSet ++= "  // 生成宏定义\n"
    instSet ++= genMacroDefs()
    instSet ++=
       """
         |}
         |""".stripMargin
    // 生成JsonInstSet.scala文件
    val file = new File("src/main/scala/JsonInstSet.scala")
    val bw = new BufferedWriter(new FileWriter(file))
    bw.write(instSet.toString())
    bw.close()
//    println(instSet)
  }

  def main(args: Array[String]): Unit = {
//    loadInfo()
//    println(genSignalValueDefs())
//    println(genSignalDefs())
//    println(genMaskedInstructs())
//    println(loadInstructDecodeInfo())
    genInstSet()
  }
}


