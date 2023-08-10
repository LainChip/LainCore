// -*- coding: utf-8 -*-
// @Time    : 2023/7/10 上午10:36
// @Author  : SuYang
// @File    : 
// @Software: IntelliJ IDEA 
// @Comment :

import spinal.core.{Data, HardType, Nameable}

class Signal[T <: Data](_dataType : => T) extends HardType[T](_dataType) with Nameable {
  def dataType: T = apply()
  setWeakName(this.getClass.getSimpleName.replace("$",""))
}
