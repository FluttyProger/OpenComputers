package li.cil.oc.server.component

import li.cil.oc.Settings
import li.cil.oc.api.driver.EnvironmentHost
import li.cil.oc.api.machine.Arguments
import li.cil.oc.api.machine.Callback
import li.cil.oc.api.machine.Context
import li.cil.oc.common.tileentity.traits.BundledRedstoneAware

trait RedstoneBundled extends RedstoneVanilla {
  override def redstone: EnvironmentHost with BundledRedstoneAware

  @Callback(direct = true, doc = """function(side:number[, color:number]):number or table -- Get the bundled redstone input on the specified side and with the specified color.""")
  def getBundledInput(context: Context, args: Arguments): Array[AnyRef] = {
    val side = checkSide(args, 0)
    if (args.optAny(1, null) == null)
      result(redstone.bundledInput(side).zipWithIndex.map(_.swap).toMap)
    else
      result(redstone.bundledInput(side, checkColor(args, 1)))
  }

  @Callback(direct = true, doc = """function(side:number[, color:number]):number or table -- Get the bundled redstone output on the specified side and with the specified color.""")
  def getBundledOutput(context: Context, args: Arguments): Array[AnyRef] = {
    val side = checkSide(args, 0)
    if (args.optAny(1, null) == null)
      result(redstone.bundledOutput(side).zipWithIndex.map(_.swap).toMap)
    else
      result(redstone.bundledOutput(side, checkColor(args, 1)))
  }

  @Callback(doc = """function(side:number, color:number, value:number):number -- Set the bundled redstone output on the specified side and with the specified color.""")
  def setBundledOutput(context: Context, args: Arguments): Array[AnyRef] = {
    val side = checkSide(args, 0)
    if (args.isTable(1)) {
      val table = args.checkTable(1)
      (0 to 15).map(color => (color, table.get(color))).foreach {
        case (color, number: Number) => redstone.bundledOutput(side, color, number.intValue())
        case _ =>
      }
      if (Settings.get.redstoneDelay > 0)
        context.pause(Settings.get.redstoneDelay)
      result(true)
    }
    else {
      val color = checkColor(args, 1)
      val value = args.checkInteger(2)
      redstone.bundledOutput(side, color, value)
      if (Settings.get.redstoneDelay > 0)
        context.pause(Settings.get.redstoneDelay)
      result(redstone.bundledOutput(side, color))
    }
  }

  // ----------------------------------------------------------------------- //

  private def checkColor(args: Arguments, index: Int): Int = {
    val color = args.checkInteger(index)
    if (color < 0 || color > 15)
      throw new IllegalArgumentException("invalid color")
    color
  }
}
