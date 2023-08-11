// -*- coding: utf-8 -*-
// @Time    : 2023/7/9 下午9:46
// @Author  : SuYang
// @File    :
// @Software: IntelliJ IDEA
// @Comment :
import scala.annotation.tailrec
import scala.collection.mutable
import spinal.core._
import spinal.lib._

object Simplify {
  private val cache = mutable.LinkedHashMap[Bits, mutable.LinkedHashMap[Masked, Bool]]()

  private def getCache(addr: Bits) = cache.getOrElseUpdate(addr, mutable.LinkedHashMap[Masked, Bool]())

  // Generate terms logic for the given input
  /*
    这里输入的terms是经过化简的译码信号的某一位的合取范式
    这是一个masked序列，包含所有可以使该位译码信号为真的逻辑
    如果不使用cache这行代码写作
    def logicOf(input: Bits, terms: Seq[Masked]): Bool = terms.map(_ === input).asBits.orR
   */
  def logicOf(input: Bits, terms: Seq[Masked]): Bool = terms.map(t => getCache(input).getOrElseUpdate(t, t === input)).asBits.orR
  def logicOfWithoutCache(input: Bits, terms: Seq[Masked]): Bool = terms.map(_ === input).asBits.orR

  // Return a new term with only one bit difference with 'term' and not included in falseTerms. above => 0 to 1 dif, else 1 to 0 diff
  private def genImplicantsDontCare(falseTerms: Seq[Masked], term: Masked, bits: Int, above: Boolean): Masked = {
    for (i <- 0 until bits; if term.care.testBit(i)) {
      var t: Masked = null
      if (above) {
        if (!term.value.testBit(i))
          t = Masked(term.value.setBit(i), term.care)
      } else {
        if (term.value.testBit(i))
          t = Masked(term.value.clearBit(i), term.care)
      }
      if (t != null && !falseTerms.exists(_.intersects(t))) {
        t.isPrime = false
        return t
      }
    }
    null
  }

  def getPrimeImplicantsByTrueAndFalse(trueTerms: Seq[Masked], falseTerms: Seq[Masked], inputWidth: Int): Seq[Masked] = {
    val primes = mutable.LinkedHashSet[Masked]()
    trueTerms.foreach(_.isPrime = true)
    falseTerms.foreach(_.isPrime = true)
    // 根据关心位（care count）分组
    val trueTermByCareCount = (inputWidth to 0 by -1).map(b => trueTerms.filter(b == _.care.bitCount))
    //table ==> [Vector[HashSet[Masked]]](careCount)(bitSetCount), table是一个二维数组
    val table = trueTermByCareCount.map(c => (0 to inputWidth).map(b => mutable.Set(c.filter(b == _.value.bitCount): _*)))

    for (i <- 0 to inputWidth) {
      //Expends explicit terms
      for (j <- 0 until inputWidth - i) {
        for (term <- table(i)(j)) {
          table(i + 1)(j) ++= table(i)(j + 1).withFilter(_.isSimilarOneBitDifSmaller(term)).map(_.mergeOneBitDifSmaller(term))
        }
      }
      //Expends implicit don't care terms
      for (j <- 0 until inputWidth - i) {
        for (prime <- table(i)(j).withFilter(_.isPrime)) {
          val dc = genImplicantsDontCare(falseTerms, prime, inputWidth, above = true)
          if (dc != null)
            table(i + 1)(j) += dc mergeOneBitDifSmaller prime
        }

        for (prime <- table(i)(j + 1).withFilter(_.isPrime)) {
          val dc = genImplicantsDontCare(falseTerms, prime, inputWidth, above = false)
          if (dc != null)
            table(i + 1)(j) += prime mergeOneBitDifSmaller dc
        }
      }

      // 从表中收集所有被标记为“主要蕴涵项”的项，并将它们添加到一个可变的集合 primes 中
      for (r <- table(i))
        for (p <- r; if p.isPrime)
          primes += p
    }


    // primes 集合中存储了所有的主要蕴涵项
    // optimise 函数用于优化这些蕴涵项，通过移除重复的项来减少集合的大小
    /*
      optimise 函数递归地执行以下操作：
      找到所有可以被其他蕴涵项替换的蕴涵项。
      如果找到了这样的蕴涵项，就从 primes 集合中移除关心位数量最大的一个。
     */
    @tailrec
    def optimise(): Unit = {
      val duplicates = primes.filter(prime => verifyTrueFalse(primes.filterNot(_ == prime), trueTerms, falseTerms))
      if (duplicates.nonEmpty) {
        primes -= duplicates.maxBy(_.care.bitCount)
        optimise()
      }
    }

    optimise()

    // 检查优化后的 primes 集合是否正确地表示了所有的真项和假项
    verifyTrueFalse(primes, trueTerms, falseTerms) // useful ??
    var duplication = 0
    for (prime <- primes) {
      if (verifyTrueFalse(primes.filterNot(_ == prime), trueTerms, falseTerms)) {
        duplication += 1
      }
    }
    if (duplication != 0) {
      PendingError(s"Duplicated primes : $duplication")
    }

    // 将优化后的 primes 集合转换为序列（Seq），并作为函数的返回值
    primes.toSeq
  }

  // Verify that the 'terms' doesn't violate the trueTerms ++ falseTerms spec
  // 该函数的作用是验证一个布尔代数表达式中的一些最小项（terms）是否包含在给定的真值表中
  private def verifyTrueFalse(terms: Iterable[Masked], trueTerms: Seq[Masked], falseTerms: Seq[Masked]): Boolean = {
    trueTerms.forall(trueTerm => terms.exists(_ covers trueTerm)) && falseTerms.forall(falseTerm => !terms.exists(_ covers falseTerm))
  }

  private def checkTrue(terms: Iterable[Masked], trueTerms: Seq[Masked]): Boolean = {
    trueTerms.forall(trueTerm => terms.exists(_ covers trueTerm))
  }

  def getPrimeImplicantsByTrue(trueTerms: Seq[Masked], inputWidth: Int): Seq[Masked] = getPrimeImplicantsByTrueAndDontCare(trueTerms, Nil, inputWidth)

  // Return primes implicants for the trueTerms, default value is False.
  // You can insert don't care values by adding non-prime implicants in the trueTerms
  // Will simplify the trueTerms from the most constrained ones to the least constrained ones
  def getPrimeImplicantsByTrueAndDontCare(trueTerms: Seq[Masked], dontCareTerms: Seq[Masked], inputWidth: Int): Seq[Masked] = {
    val primes = mutable.LinkedHashSet[Masked]()
    trueTerms.foreach(_.isPrime = true)
    dontCareTerms.foreach(_.isPrime = false)
    val termsByCareCount = (inputWidth to 0 by -1).map(b => (trueTerms ++ dontCareTerms).filter(b == _.care.bitCount))
    //table[Vector[HashSet[Masked]]](careCount)(bitSetCount)
    val table = termsByCareCount.map(c => (0 to inputWidth).map(b => collection.mutable.Set(c.filter(m => b == m.value.bitCount): _*)))
    for (i <- 0 to inputWidth) {
      for (j <- 0 until inputWidth - i) {
        for (term <- table(i)(j)) {
          table(i + 1)(j) ++= table(i)(j + 1).withFilter(_.isSimilarOneBitDifSmaller(term)).map(_.mergeOneBitDifSmaller(term))
        }
      }
      for (r <- table(i))
        for (p <- r; if p.isPrime)
          primes += p
    }


    @tailrec
    def optimise(): Unit = {
      val duplicates = primes.filter(prime => checkTrue(primes.filterNot(_ == prime), trueTerms))
      if (duplicates.nonEmpty) {
        primes -= duplicates.maxBy(_.care.bitCount)
        optimise()
      }
    }

    optimise()


    var duplication = 0
    for (prime <- primes) {
      if (checkTrue(primes.filterNot(_ == prime), trueTerms)) {
        duplication += 1
      }
    }
    if (duplication != 0) {
      PendingError(s"Duplicated primes : $duplication")
    }
    primes.toSeq
  }


}
