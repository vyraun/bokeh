import * as _ from "underscore"
import {Events} from "./events"
import * as enums from "./enums"
import * as svg_colors from "./util/svg_colors"
import {valid_rgb} from "./util/color"

#
# Property base class
#

export class Property
  _.extend(@prototype, Events)

  dataspec: false
  specifiers: ['field', 'value']

  constructor: ({@obj, @attr, @default_value}) ->
    @_init(false)

    # TODO (bev) Quick fix, see https://github.com/bokeh/bokeh/pull/2684
    @listenTo(@obj, "change:#{@attr}", () =>
      @_init()
      @obj.trigger("propchange")
    )

  update: () -> @_init()

  # ----- customizable policies

  init: () ->

  transform: (values) -> values

  validate: (value) ->

  # ----- property accessors

  value: (do_spec_transform=true) ->
    if _.isUndefined(@spec.value)
      throw new Error("attempted to retrieve property value for property without value specification")
    ret = @transform([@spec.value])[0]
    if @spec.transform? and do_spec_transform
      ret = @spec.transform.compute(ret)
    return ret

  array: (source) ->
    if not @dataspec
      throw new Error("attempted to retrieve property array for non-dataspec property")
    data = source.data
    if @spec.field?
      if @spec.field of data
        ret = @transform(source.get_column(@spec.field))
      else
        throw new Error("attempted to retrieve property array for nonexistent field '#{@spec.field}'")
    else
      length = source.get_length()
      length = 1 if not length?
      value = @value(false) # don't apply any spec transform
      ret = (value for i in [0...length])

    if @spec.transform?
      ret = @spec.transform.v_compute(ret)
    return ret

  # ----- private methods

  _init: (trigger=true) ->
    obj = @obj
    if not obj?
      throw new Error("missing property object")

    # instanceof was failing! circular import?
    if not obj.properties?
      throw new Error("property object must be a HasProps")

    attr = @attr
    if not attr?
      throw new Error("missing property attr")

    attr_value = obj.getv(attr)

    if _.isUndefined(attr_value)
      default_value = @default_value

      attr_value = switch
        when _.isUndefined(default_value) then null
        when _.isArray(default_value)     then _.clone(default_value)
        when _.isFunction(default_value)  then default_value(obj)
        else                                   default_value

      obj.setv(attr, attr_value, {silent: true, defaults: true})

    # if _.isObject(attr_value) and not _.isArray(attr_value) and not attr_value.properties?
    #   @spec = attr_value
    #   if _.size(_.pick.apply(null, [@spec].concat(@specifiers))) != 1
    #     throw new Error("Invalid property specifier #{JSON.stringify(@spec)}, must have exactly one of #{@specifiers}")

    if _.isArray(attr_value)
      @spec = {value: attr_value}

    # is there a better way to check for "specs" ? this seems fragile
    else if _.isObject(attr_value) and _.size(_.pick.apply(null, [attr_value].concat(@specifiers))) == 1
      @spec = attr_value

    else
      @spec = {value: attr_value}

    if @spec.field? and not _.isString(@spec.field)
      throw new Error("field value for property '#{attr}' is not a string")

    if @spec.value?
      @validate(@spec.value)

    @init()

    if trigger
      @trigger("change")

#
# Simple Properties
#

export simple_prop = (name, pred) ->
  class Prop extends Property
    toString: () -> "#{name}(obj: #{@obj.id}, spec: #{JSON.stringify(@spec)})"
    validate: (value) ->
      if not pred(value)
        throw new Error("#{name} property '#{@attr}' given invalid value: #{value}")

export class Any extends simple_prop("Any", (x) -> true)

export class Array extends simple_prop("Array", (x) -> _.isArray(x) or x instanceof Float64Array)

export class Bool extends simple_prop("Bool", _.isBoolean)
export Boolean = Bool

export class Color extends simple_prop("Color", (x) ->
  svg_colors[x.toLowerCase()]? or x.substring(0, 1) == "#" or valid_rgb(x)
)

export class Instance extends simple_prop("Instance", (x) -> x.properties?)

# TODO (bev) separate booleans?
export class Number extends simple_prop("Number", (x) -> _.isNumber(x) or _.isBoolean(x))
export Int = Number

# TODO extend Number instead of copying it's predicate
#class Percent extends Number("Percent", (x) -> 0 <= x <= 1.0)
export class Percent extends simple_prop("Number", (x) -> (_.isNumber(x) or _.isBoolean(x)) and (0 <= x <= 1.0) )

export class String extends simple_prop("String", _.isString)

# TODO (bev) don't think this exists python side
export class Font extends String


#
# Enum properties
#

export enum_prop = (name, enum_values) ->
  class Enum extends simple_prop(name, (x) -> x in enum_values)
    toString: () -> "#{name}(obj: #{@obj.id}, spec: #{JSON.stringify(@spec)})"

export class Anchor extends enum_prop("Anchor", enums.LegendLocation)

export class AngleUnits extends enum_prop("AngleUnits", enums.AngleUnits)

export class Direction extends enum_prop("Direction", enums.Direction)
  transform: (values) ->
    result = new Uint8Array(values.length)
    for i in [0...values.length]
      switch values[i]
        when 'clock'     then result[i] = false
        when 'anticlock' then result[i] = true
    return result

export class Dimension extends enum_prop("Dimension", enums.Dimension)

export class Dimensions extends enum_prop("Dimensions", enums.Dimensions)

export class FontStyle extends enum_prop("FontStyle", enums.FontStyle)

export class LineCap extends enum_prop("LineCap", enums.LineCap)

export class LineJoin extends enum_prop("LineJoin", enums.LineJoin)

export class LegendLocation extends enum_prop("LegendLocation", enums.LegendLocation)

export class Location extends enum_prop("Location", enums.Location)

export class Orientation extends enum_prop("Orientation", enums.Orientation)

export class TextAlign extends enum_prop("TextAlign", enums.TextAlign)

export class TextBaseline extends enum_prop("TextBaseline", enums.TextBaseline)

export class RenderLevel extends enum_prop("RenderLevel", enums.RenderLevel)

export class RenderMode extends enum_prop("RenderMode", enums.RenderMode)

export class SizingMode extends enum_prop("SizingMode", enums.SizingMode)

export class SpatialUnits extends enum_prop("SpatialUnits", enums.SpatialUnits)

export class Distribution extends enum_prop("Distribution", enums.DistributionTypes)

export class TransformStepMode extends enum_prop("TransformStepMode", enums.TransformStepModes)

#
# Units Properties
#

export units_prop = (name, valid_units, default_units) ->
  class UnitsProp extends Number
    toString: () -> "#{name}(obj: #{@obj.id}, spec: #{JSON.stringify(@spec)})"
    init: () ->
      if not @spec.units?
        @spec.units = default_units

      # TODO (bev) remove this later, it's just for temporary compat
      @units = @spec.units

      units = @spec.units
      if units not in valid_units
        throw new Error("#{name} units must be one of #{valid_units}, given invalid value: #{units}")

export class Angle extends units_prop("Angle", enums.AngleUnits, "rad")
  transform: (values) ->
    if @spec.units == "deg"
      values = (x * Math.PI/180.0 for x in values)
    values = (-x for x in values)
    return super(values)

export class Distance extends units_prop("Distance", enums.SpatialUnits, "data")

#
# DataSpec properties
#

export class AngleSpec extends Angle
  dataspec: true

export class ColorSpec extends Color
  dataspec: true

export class DirectionSpec extends Distance
  dataspec: true

export class DistanceSpec extends Distance
  dataspec: true

export class FontSizeSpec extends String
  dataspec: true

export class NumberSpec extends Number
  dataspec: true

export class StringSpec extends String
  dataspec: true
