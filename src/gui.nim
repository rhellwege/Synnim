import raylib, raymath, math, tables, locks
import "synth.nim"

var
  activeComponentTable: Table[pointer, bool]

# imgui style
proc knob*(center: Vector2, radius: float, `low`: float, `high`: float, increment: float, modifier: var float) =
  if distance(getMousePosition(), center) <= radius:
    if isMouseButtonDown(Left):
      activeComponentTable[addr modifier] = true
      
  if isMouseButtonReleased(Left):
    activeComponentTable[addr modifier] = false
  if activeComponentTable.contains(addr modifier) and activeComponentTable[addr modifier]:
    modifier += -getMouseDelta().y * increment
    modifier = clamp(modifier, `low`, `high`)
    setMouseCursor(MouseCursor.ResizeNs)
  drawCircle(center, radius, DarkGray)
  let angle = remap(modifier, `low`, `high`, PI/6, (2*PI)-(PI/6)) + (PI / 2)
  drawLine(center, center + Vector2(x: radius*cos(angle), y: radius*sin(angle)), White)

proc button*(t: string, pos: Vector2, f: float): bool =
  const padding: float = 5.0
  let s = measureText(getFontDefault(), cstring t, f, padding) + Vector2(x: padding*2, y: 0)
  drawRectangle(pos, s, DarkGray)
  drawText(getFontDefault(), cstring t, pos + Vector2(x: padding, y: 0), f, padding, White)
  let mousePos = getMousePosition()
  result = false
  if mousePos.x >= pos.x and mousePos.x <= pos.x + s.x and mousePos.y >= pos.y and mousePos.y <= pos.y + s.y:
    setMouseCursor(MouseCursor.PointingHand)
    if isMouseButtonPressed(Left):
      result = true
  return

proc drawAnalyzerToRect*(r: Rectangle, wavelengths: float) =
    # assert(r.width.toInt() < snapshotSize)
    # requestSnapshot(snapshotBuffer, r.width.toInt) # communicate with the synth
    # for xCoord in countup(0, (r.width-1).toInt()):
    #     #let sampleX = xCoord * (snapshotSize.toFloat() / r.width).toInt()
    #     let sampleY = ((r.height/2)*(int16ToSample(snapshotBuffer[xCoord]))) + (
    #             r.height / 2)
    #     drawPixel(Vector2(x: xCoord.toFloat(), y: sampleY), Red)
    var t = 0.0
    let dt = wavelengths/(getScreenWidth().toFloat()*baseFreq)
    for x in countUp(0, getScreenWidth()-1):
      withLock(audioMutex):
        let sampleY = ((r.height/2)*(finalSample(t))) + (r.height / 2)
        t += dt
        drawPixel(Vector2(x: x.toFloat(), y: sampleY), Red)

proc drawEnvelopeToRect*(e: EnvelopeADSR, r: Rectangle) =
  let totalTime = e.attackTime + e.decayTime + e.releaseTime
  # attack line
  let attackPixels = Vector2(x: (e.attackTime/totalTime)*r.width, y: (r.y + r.height) - (e.attackVolume * r.height))
  drawLine(Vector2(x: r.x, y: r.y + r.height), attackPixels, Red)
  drawRectangleLines(r, 2.0, Red)
  discard

proc drawOscillatorToRect*(o: Oscillator, r: Rectangle) =
  discard

proc drawSynthToRect*(s: Synth, r: Rectangle) =
  discard
