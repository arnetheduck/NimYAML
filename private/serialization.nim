#            NimYAML - YAML implementation in Nim
#        (c) Copyright 2015 Felix Krause
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

proc newConstructionContext*(): ConstructionContext =
  new(result)
  result.refs = initTable[AnchorId, pointer]()

proc newSerializationContext*(s: AnchorStyle): SerializationContext =
  new(result)
  result.refs = initTable[pointer, AnchorId]()
  result.style = s
  result.nextAnchorId = 0.AnchorId
    
template presentTag*(t: typedesc, ts: TagStyle): TagId =
  ## Get the TagId that represents the given type in the given style
  if ts == tsNone: yTagQuestionMark else: yamlTag(t)

proc lazyLoadTag(uri: string): TagId {.inline, raises: [].} =
  try: result = serializationTagLibrary.tags[uri]
  except KeyError: result = serializationTagLibrary.registerUri(uri)

proc safeTagUri(id: TagId): string {.raises: [].} =
  try:
    let uri = serializationTagLibrary.uri(id)
    if uri.len > 0 and uri[0] == '!': return uri[1..uri.len - 1]
    else: return uri
  except KeyError:
    # cannot happen (theoretically, you known)
    assert(false)

template constructScalarItem*(s: var YamlStream, i: expr,
                              t: typedesc, content: untyped) =
  ## Helper template for implementing ``constructObject`` for types that
  ## are constructed from a scalar. ``i`` is the identifier that holds
  ## the scalar as ``YamlStreamEvent`` in the content. Exceptions raised in
  ## the content will be automatically catched and wrapped in
  ## ``YamlConstructionError``, which will then be raised.
  let i = s.next() 
  if i.kind != yamlScalar:
    raise newException(YamlConstructionError, "Expected scalar")
  try: content
  except YamlConstructionError: raise
  except Exception:
    var e = newException(YamlConstructionError,
        "Cannot construct to " & name(t) & ": " & item.scalarContent)
    e.parent = getCurrentException()
    raise e

proc yamlTag*(T: typedesc[string]): TagId {.inline, noSideEffect, raises: [].} =
  yTagString

proc constructObject*(s: var YamlStream, c: ConstructionContext,
                      result: var string)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## costructs a string from a YAML scalar
  constructScalarItem(s, item, string):
    result = item.scalarContent

proc representObject*(value: string, ts: TagStyle,
        c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a string as YAML scalar
  result = iterator(): YamlStreamEvent =
    yield scalarEvent(value, tag, yAnchorNone)

proc constructObject*[T: int8|int16|int32|int64](
    s: var YamlStream, c: ConstructionContext, result: var T)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs an integer value from a YAML scalar
  constructScalarItem(s, item, T):
    result = T(parseBiggestInt(item.scalarContent))

template constructObject*(s: var YamlStream, c: ConstructionContext,
                          result: var int) =
  ## calling this will raise a compiler error because ``int`` is not supported
  {.fatal: "The length of `int` is platform dependent. Use int[8|16|32|64].".}
  discard

proc representObject*[T: int8|int16|int32|int64](value: T, ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents an integer value as YAML scalar
  result = iterator(): YamlStreamEvent =
    yield scalarEvent($value, tag, yAnchorNone)

template representObject*(value: int, tagStyle: TagStyle,
                          c: SerializationContext, tag: TagId): RawYamlStream =
  ## calling this will raise a compiler error because ``int`` is not supported
  {.fatal: "The length of `int` is platform dependent. Use int[8|16|32|64].".}
  discard

{.push overflowChecks: on.}
proc parseBiggestUInt(s: string): uint64 =
  result = 0
  for c in s:
    if c in {'0'..'9'}: result *= 10.uint64 + (uint64(c) - uint64('0'))
    elif c == '_': discard
    else: raise newException(ValueError, "Invalid char in uint: " & c)
{.pop.}

proc constructObject*[T: uint8|uint16|uint32|uint64](
    s: var YamlStream, c: ConstructionContext, result: var T)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## construct an unsigned integer value from a YAML scalar
  constructScalarItem(s, item, T):
    result = T(parseBiggestUInt(item.scalarContent))

template constructObject*(s: var YamlStream, c: ConstructionContext,
                          result: var uint) =
  ## calling this will raise a compiler error because ``uint`` is not
  ## supported
  {.fatal:
      "The length of `uint` is platform dependent. Use uint[8|16|32|64].".}
  discard

proc representObject*[T: uint8|uint16|uint32|uint64](value: T, ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents an unsigned integer value as YAML scalar
  result = iterator(): YamlStreamEvent =
    yield scalarEvent($value, tag, yAnchorNone)

template representObject*(value: uint, ts: TagStyle, c: SerializationContext,
    tag: TagId): RawYamlStream =
  ## calling this will raise a compiler error because ``uint`` is not
  ## supported
  {.fatal:
      "The length of `uint` is platform dependent. Use uint[8|16|32|64].".}
  discard

proc constructObject*[T: float32|float64](
    s: var YamlStream, c: ConstructionContext, result: var T)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## construct a float value from a YAML scalar
  constructScalarItem(s, item, T):
    let hint = guessType(item.scalarContent)
    case hint
    of yTypeFloat: result = T(parseBiggestFloat(item.scalarContent))
    of yTypeFloatInf:
        if item.scalarContent[0] == '-': result = NegInf
        else: result = Inf
    of yTypeFloatNaN: result = NaN
    else:
      raise newException(YamlConstructionError,
          "Cannot construct to float: " & item.scalarContent)

template constructObject*(s: var YamlStream, c: ConstructionContext,
                          result: var float) =
  ## calling this will raise a compiler error because ``float`` is not
  ## supported
  {.fatal: "The length of `float` is platform dependent. Use float[32|64].".}

proc representObject*[T: float32|float64](value: T, ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a float value as YAML scalar
  result = iterator(): YamlStreamEvent =
    var asString: string
    case value
    of Inf: asString = ".inf"
    of NegInf: asString = "-.inf"
    of NaN: asString = ".nan"
    else: asString = $value
    yield scalarEvent(asString, tag, yAnchorNone)

template representObject*(value: float, tagStyle: TagStyle,
                          c: SerializationContext, tag: TagId): RawYamlStream =
  ## calling this will result in a compiler error because ``float`` is not
  ## supported
  {.fatal: "The length of `float` is platform dependent. Use float[32|64].".}

proc yamlTag*(T: typedesc[bool]): TagId {.inline, raises: [].} = yTagBoolean

proc constructObject*(s: var YamlStream, c: ConstructionContext,
                      result: var bool)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a bool value from a YAML scalar
  constructScalarItem(s, item, bool):
    case guessType(item.scalarContent)
    of yTypeBoolTrue: result = true
    of yTypeBoolFalse: result = false
    else:
      raise newException(YamlConstructionError,
          "Cannot construct to bool: " & item.scalarContent)
        
proc representObject*(value: bool, ts: TagStyle, c: SerializationContext,
    tag: TagId): RawYamlStream  {.raises: [].} =
  ## represents a bool value as a YAML scalar
  result = iterator(): YamlStreamEvent =
    yield scalarEvent(if value: "y" else: "n", tag, yAnchorNone)

proc constructObject*(s: var YamlStream, c: ConstructionContext,
                      result: var char)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a char value from a YAML scalar
  constructScalarItem(s, item, char):
    if item.scalarContent.len != 1:
      raise newException(YamlConstructionError,
          "Cannot construct to char (length != 1): " & item.scalarContent)
    else: result = item.scalarContent[0]

proc representObject*(value: char, ts: TagStyle, c: SerializationContext,
    tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a char value as YAML scalar
  result = iterator(): YamlStreamEvent =
    yield scalarEvent("" & value, tag, yAnchorNone)

proc yamlTag*[I](T: typedesc[seq[I]]): TagId {.inline, raises: [].} =
  let uri = "!nim:system:seq(" & safeTagUri(yamlTag(I)) & ')'
  result = lazyLoadTag(uri)

proc yamlTag*[I](T: typedesc[set[I]]): TagId {.inline, raises: [].} =
  let uri = "!nim:system:set(" & safeTagUri(yamlTag(I)) & ')'
  result = lazyLoadTag(uri)

proc constructObject*[T](s: var YamlStream, c: ConstructionContext,
                         result: var seq[T])
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim seq from a YAML sequence
  let event = s.next()
  if event.kind != yamlStartSeq:
    raise newException(YamlConstructionError, "Expected sequence start")
  result = newSeq[T]()
  while s.peek().kind != yamlEndSeq:
    var item: T
    constructChild(s, c, item)
    result.add(item)
  discard s.next()

proc constructObject*[T](s: var YamlStream, c: ConstructionContext,
                         result: var set[T])
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim seq from a YAML sequence
  let event = s.next()
  if event.kind != yamlStartSeq:
    raise newException(YamlConstructionError, "Expected sequence start")
  result = {}
  while s.peek().kind != yamlEndSeq:
    var item: T
    constructChild(s, c, item)
    result.incl(item)
  discard s.next()

proc representObject*[T](value: seq[T]|set[T], ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a Nim seq as YAML sequence
  result = iterator(): YamlStreamEvent =
    let childTagStyle = if ts == tsRootOnly: tsNone else: ts
    yield startSeqEvent(tag)
    for item in value:
      var events = representChild(item, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
    yield endSeqEvent()

proc yamlTag*[I, V](T: typedesc[array[I, V]]): TagId {.inline, raises: [].} =
  const rangeName = name(I)
  let uri = "!nim:system:array(" & rangeName[6..rangeName.high()] & "," &
      safeTagUri(yamlTag(V)) & ')'
  result = lazyLoadTag(uri)

proc constructObject*[I, T](s: var YamlStream, c: ConstructionContext,
                         result: var array[I, T])
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim array from a YAML sequence
  var event = s.next()
  if event.kind != yamlStartSeq:
    raise newException(YamlConstructionError, "Expected sequence start")
  for index in low(I)..high(I):
    event = s.peek()
    if event.kind == yamlEndSeq:
      raise newException(YamlConstructionError, "Too few array values")
    constructChild(s, c, result[index])
  event = s.next()
  if event.kind != yamlEndSeq:
    raise newException(YamlConstructionError, "Too much array values")

proc representObject*[I, T](value: array[I, T], ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a Nim array as YAML sequence
  result = iterator(): YamlStreamEvent =
    let childTagStyle = if ts == tsRootOnly: tsNone else: ts
    yield startSeqEvent(tag)
    for item in value:
      var events = representChild(item, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
    yield endSeqEvent()
    
proc yamlTag*[K, V](T: typedesc[Table[K, V]]): TagId {.inline, raises: [].} =
  try:
    let uri = "!nim:tables:Table(" & safeTagUri(yamlTag(K)) & "," &
        safeTagUri(yamlTag(V)) & ")"
    result = lazyLoadTag(uri)
  except KeyError:
    # cannot happen (theoretically, you know)
    assert(false)

proc constructObject*[K, V](s: var YamlStream, c: ConstructionContext,
                            result: var Table[K, V])
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim Table from a YAML mapping
  let event = s.next()
  if event.kind != yamlStartMap:
    raise newException(YamlConstructionError, "Expected map start, got " &
                       $event.kind)
  result = initTable[K, V]()
  while s.peek.kind != yamlEndMap:
    var
      key: K
      value: V
    constructChild(s, c, key)
    constructChild(s, c, value)
    if result.contains(key):
      raise newException(YamlConstructionError, "Duplicate table key!")
    result[key] = value
  discard s.next()

proc representObject*[K, V](value: Table[K, V], ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises:[].} =
  ## represents a Nim Table as YAML mapping
  result = iterator(): YamlStreamEvent =
    let childTagStyle = if ts == tsRootOnly: tsNone else: ts
    yield startMapEvent(tag)
    for key, value in value.pairs:
      var events = representChild(key, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
      events = representChild(value, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
    yield endMapEvent()

proc yamlTag*[K, V](T: typedesc[OrderedTable[K, V]]): TagId
    {.inline, raises: [].} =
  try:
    let uri = "!nim:tables:OrderedTable(" & safeTagUri(yamlTag(K)) & "," &
        safeTagUri(yamlTag(V)) & ")"
    result = lazyLoadTag(uri)
  except KeyError:
    # cannot happen (theoretically, you know)
    assert(false)

proc constructObject*[K, V](s: var YamlStream, c: ConstructionContext,
                            result: var OrderedTable[K, V])
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim OrderedTable from a YAML mapping
  let event = s.next()
  if event.kind != yamlStartSeq:
    raise newException(YamlConstructionError, "Expected seq start, got " &
                       $event.kind)
  result = initOrderedTable[K, V]()
  while s.peek.kind != yamlEndSeq:
    var
      key: K
      value: V
    if s.next().kind != yamlStartMap:
      raise newException(YamlConstructionError,
          "Expected map start, got " & $event.kind)
    constructChild(s, c, key)
    constructChild(s, c, value)
    if s.next().kind != yamlEndMap:
      raise newException(YamlConstructionError,
          "Expected map end, got " & $event.kind)
    if result.contains(key):
      raise newException(YamlConstructionError, "Duplicate table key!")
    result.add(key, value)
  discard s.next()

proc representObject*[K, V](value: OrderedTable[K, V], ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  result = iterator(): YamlStreamEvent =
    let childTagStyle = if ts == tsRootOnly: tsNone else: ts
    yield startSeqEvent(tag)
    for key, value in value.pairs:
      yield startMapEvent()
      var events = representChild(key, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
      events = representChild(value, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
      yield endMapEvent()
    yield endSeqEvent()

template yamlTag*(T: typedesc[object|enum]): expr =
  var uri = when compiles(yamlTagId(T)): yamlTagId(T) else:
      "!nim:custom:" & (typetraits.name(type(T)))
  try: serializationTagLibrary.tags[uri]
  except KeyError: serializationTagLibrary.registerUri(uri)

template yamlTag*(T: typedesc[tuple]): expr =
  var
    i: T
    uri = "!nim:tuple("
    first = true
  for name, value in fieldPairs(i):
    if first: first = false
    else: uri.add(",")
    uri.add(safeTagUri(yamlTag(type(value))))
  uri.add(")")
  try: serializationTagLibrary.tags[uri]
  except KeyError: serializationTagLibrary.registerUri(uri)

proc constructObject*[O: object|tuple](
    s: var YamlStream, c: ConstructionContext, result: var O)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim object or tuple from a YAML mapping
  let e = s.next()
  if e.kind != yamlStartMap:
    raise newException(YamlConstructionError, "Expected map start, got " &
                       $e.kind)
  while s.peek.kind != yamlEndMap:
    let e = s.next()
    if e.kind != yamlScalar:
      raise newException(YamlConstructionError,
          "Expected field name, got " & $e.kind)
    let name = e.scalarContent
    for fname, value in fieldPairs(result):
      if fname == name:
        constructChild(s, c, value)
        break
  discard s.next()

proc representObject*[O: object|tuple](value: O, ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a Nim object or tuple as YAML mapping
  result = iterator(): YamlStreamEvent =
    let childTagStyle = if ts == tsRootOnly: tsNone else: ts
    yield startMapEvent(tag, yAnchorNone)
    for name, value in fieldPairs(value):
      yield scalarEvent(name,
          if childTagStyle == tsNone: yTagQuestionMark else:
          yTagNimField, yAnchorNone)
      var events = representChild(value, childTagStyle, c)
      while true:
        let event = events()
        if finished(events): break
        yield event
    yield endMapEvent()

proc constructObject*[O: enum](s: var YamlStream, c: ConstructionContext,
                               result: var O)
    {.raises: [YamlConstructionError, YamlStreamError].} =
  ## constructs a Nim enum from a YAML scalar
  let e = s.next()
  if e.kind != yamlScalar:
    raise newException(YamlConstructionError, "Expected scalar, got " &
                       $e.kind)
  try: result = parseEnum[O](e.scalarContent)
  except ValueError:
    var ex = newException(YamlConstructionError, "Cannot parse '" &
        e.scalarContent & "' as " & type(O).name)
    ex.parent = getCurrentException()
    raise ex

proc representObject*[O: enum](value: O, ts: TagStyle,
    c: SerializationContext, tag: TagId): RawYamlStream {.raises: [].} =
  ## represents a Nim enum as YAML scalar
  result = iterator(): YamlStreamEvent =
    yield scalarEvent($value, tag, yAnchorNone)

proc yamlTag*[O](T: typedesc[ref O]): TagId {.inline, raises: [].} = yamlTag(O)

proc constructChild*[T](s: var YamlStream, c: ConstructionContext,
                        result: var T) =
  let item = s.peek()
  case item.kind
  of yamlScalar:
    if item.scalarTag notin [yTagQuestionMark, yTagExclamationMark, yamlTag(T)]:
      raise newException(YamlConstructionError, "Wrong tag for " &
                         typetraits.name(T))
    elif item.scalarAnchor != yAnchorNone:
      raise newException(YamlConstructionError, "Anchor on non-ref type")
  of yamlStartMap:
    if item.mapTag notin [yTagQuestionMark, yamlTag(T)]:
      raise newException(YamlConstructionError, "Wrong tag for " &
                         typetraits.name(T))
    elif item.mapAnchor != yAnchorNone:
      raise newException(YamlConstructionError, "Anchor on non-ref type")
  of yamlStartSeq:
    if item.seqTag notin [yTagQuestionMark, yamlTag(T)]:
      raise newException(YamlConstructionError, "Wrong tag for " &
                         typetraits.name(T))
    elif item.seqAnchor != yAnchorNone:
      raise newException(YamlConstructionError, "Anchor on non-ref type")
  else: assert false
  constructObject(s, c, result)

proc constructChild*[O](s: var YamlStream, c: ConstructionContext,
                        result: var ref O) =
  var e = s.peek()
  if e.kind == yamlScalar:
    if e.scalarTag == yTagNull or (e.scalarTag == yTagQuestionMark and
        guessType(e.scalarContent) == yTypeNull):
      result = nil
      discard s.next()
      return
  elif e.kind == yamlAlias:
    try:
      result = cast[ref O](c.refs[e.aliasTarget])
      discard s.next()
      return
    except KeyError: assert(false)
  new(result)
  template removeAnchor(anchor: var AnchorId) {.dirty.} =
    if anchor != yAnchorNone:
      assert(not c.refs.hasKey(anchor))
      c.refs[anchor] = cast[pointer](result)
      anchor = yAnchorNone
  
  case e.kind
  of yamlScalar: removeAnchor(e.scalarAnchor)
  of yamlStartMap: removeAnchor(e.mapAnchor)
  of yamlStartSeq: removeAnchor(e.seqAnchor)
  else: assert(false)
  s.peek = e
  try: constructChild(s, c, result[])
  except YamlConstructionError, YamlStreamError, AssertionError: raise
  except Exception:
    var e = newException(YamlStreamError, getCurrentExceptionMsg())
    e.parent = getCurrentException()
    raise e

proc representChild*[O](value: O, ts: TagStyle, c: SerializationContext):
    RawYamlStream =
  result = representObject(value, ts, c, presentTag(O, ts))

proc representChild*[O](value: ref O, ts: TagStyle, c: SerializationContext):
    RawYamlStream =
  if value == nil:
    result = iterator(): YamlStreamEvent =
      yield scalarEvent("~", yTagNull)
  elif c.style == asNone: result = representChild(value[], ts, c)
  else:
    let p = cast[pointer](value)
    if c.refs.hasKey(p):
      try:
        if c.refs[p] == yAnchorNone:
          c.refs[p] = c.nextAnchorId
          c.nextAnchorId = AnchorId(int(c.nextAnchorId) + 1)
      except KeyError: assert false, "Can never happen"
      result = iterator(): YamlStreamEvent {.raises: [].} =
        var event: YamlStreamEvent
        try: event = aliasEvent(c.refs[p])
        except KeyError: assert false, "Can never happen"
        yield event
      return
    try:
      if c.style == asAlways:
        c.refs[p] = c.nextAnchorId
        c.nextAnchorId = AnchorId(int(c.nextAnchorId) + 1)
      else: c.refs[p] = yAnchorNone
      let
        a = if c.style == asAlways: c.refs[p] else: cast[AnchorId](p)
        childTagStyle = if ts == tsAll: tsAll else: tsRootOnly
      result = iterator(): YamlStreamEvent =
        var child = representChild(value[], childTagStyle, c)
        var first = child()
        assert(not finished(child))
        case first.kind 
        of yamlStartMap:
          first.mapAnchor = a
          if ts == tsNone: first.mapTag = yTagQuestionMark
        of yamlStartSeq:
          first.seqAnchor = a
          if ts == tsNone: first.seqTag = yTagQuestionMark
        of yamlScalar:
          first.scalarAnchor = a
          if ts == tsNone and guessType(first.scalarContent) != yTypeNull:
            first.scalarTag = yTagQuestionMark
        else: discard
        yield first
        while true:
          let event = child()
          if finished(child): break
          yield event
    except KeyError: assert false, "Can never happen"

proc construct*[T](s: var YamlStream, target: var T) =
  var context = newConstructionContext()
  try:
    var e = s.next()
    assert(e.kind == yamlStartDoc)
    
    constructChild(s, context, target)
    e = s.next()
    assert(e.kind == yamlEndDoc)
  except YamlConstructionError:
    raise (ref YamlConstructionError)(getCurrentException())
  except YamlStreamError:
    raise (ref YamlStreamError)(getCurrentException())
  except AssertionError:
    raise (ref AssertionError)(getCurrentException())
  except Exception:
    # may occur while calling s()
    var ex = newException(YamlStreamError, "")
    ex.parent = getCurrentException()
    raise ex

proc load*[K](input: Stream, target: var K) =
  var
    parser = newYamlParser(serializationTagLibrary)
    events = parser.parse(input)
  try: construct(events, target)
  except YamlConstructionError:
    var e = (ref YamlConstructionError)(getCurrentException())
    e.line = parser.getLineNumber()
    e.column = parser.getColNumber()
    e.lineContent = parser.getLineContent()
    raise e
  except YamlStreamError:
    let e = (ref YamlStreamError)(getCurrentException())
    if e.parent of IOError: raise (ref IOError)(e.parent)
    elif e.parent of YamlParserError: raise (ref YamlParserError)(e.parent)
    else: assert(false)

proc setAnchor(a: var AnchorId, q: var Table[pointer, AnchorId])
    {.inline.} =
  if a != yAnchorNone:
    try: a = q[cast[pointer](a)]
    except KeyError: assert false, "Can never happen"
    
proc represent*[T](value: T, ts: TagStyle = tsRootOnly,
                   a: AnchorStyle = asTidy): YamlStream =
  var
    context = newSerializationContext(a)
    objStream = iterator(): YamlStreamEvent =
      yield startDocEvent()
      var events = representChild(value, ts, context)
      while true:
        let e = events()
        if finished(events): break
        yield e
      yield endDocEvent()
  if a == asTidy:
    var objQueue = newSeq[YamlStreamEvent]()
    try:
      for event in objStream(): objQueue.add(event)
    except Exception:
      assert(false)
    var backend = iterator(): YamlStreamEvent =
      for i in countup(0, objQueue.len - 1):
        var event = objQueue[i]
        case event.kind
        of yamlStartMap: event.mapAnchor.setAnchor(context.refs)
        of yamlStartSeq: event.seqAnchor.setAnchor(context.refs)
        of yamlScalar: event.scalarAnchor.setAnchor(context.refs)
        else: discard
        yield event
    result = initYamlStream(backend)
  else: result = initYamlStream(objStream)

proc dump*[K](value: K, target: Stream, tagStyle: TagStyle = tsRootOnly,
              anchorStyle: AnchorStyle = asTidy,
              options: PresentationOptions = defaultPresentationOptions) =
  var events = represent(value,
      if options.style == psCanonical: tsAll else: tagStyle,
      if options.style == psJson: asNone else: anchorStyle)
  try: present(events, target, serializationTagLibrary, options)
  except YamlStreamError:
    # serializing object does not raise any errors, so we can ignore this
    assert false, "Can never happen"