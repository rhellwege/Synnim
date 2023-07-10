import raylib, raymath, math, tables
import "synth.nim"

const
    snapshotSize: Natural = 256*256*25

var
    snapshotBuffer: array[snapshotSize, int16]
    activeComponentTable: Table[pointer, bool]

# imgui style
proc knob*(center: Vector2, radius: float, `low`: float, `high`: float, increment: float, modifier: var float) =
  if distance(getMousePosition(), center) <= radius:
    if isMouseButtonDown(Left):
      activeComponentTable[addr modifier] = true
      setMouseCursor(MouseCursor.ResizeNs)

  if isMouseButtonReleased(Left):
    activeComponentTable[addr modifier] = false
    setMouseCursor(MouseCursor.Default)
  if activeComponentTable.contains(addr modifier) and activeComponentTable[addr modifier]:
    modifier += -getMouseDelta().y * increment
    modifier = clamp(modifier, `low`, `high`)
  drawCircle(center, radius, DarkGray)
  let angle = remap(modifier, `low`, `high`, PI/6, (2*PI)-(PI/6)) + (PI / 2)
  drawLine(center, center + Vector2(x: radius*cos(angle), y: radius*sin(angle)), White)


proc drawAnalyzerToRect*(r: Rectangle) =
    assert(r.width.toInt() < snapshotSize)
    requestSnapshot(snapshotBuffer, r.width.toInt) # communicate with the synth
    for xCoord in countup(0, (r.width-1).toInt()):
        #let sampleX = xCoord * (snapshotSize.toFloat() / r.width).toInt()
        let sampleY = ((r.height/2)*(int16ToSample(snapshotBuffer[xCoord]))) + (
                r.height / 2)
        drawPixel(Vector2(x: xCoord.toFloat(), y: sampleY), Red)

proc drawEnvelopeToRect*(e: EnvelopeADSR, r: Rectangle) =
    discard

proc drawOscillatorToRect*(o: Oscillator, r: Rectangle) =
    discard

proc drawSynthToRect*(s: Synth, r: Rectangle) =
    discard
