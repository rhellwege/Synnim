import raylib, raymath, math, tables, locks, complex
import "synth.nim"
import "signal.nim"

const
  maxFourierSamples: Natural = 2048

var
  activeComponentTable: Table[pointer, bool]
  samples: array[maxFourierSamples, float]
  frequencies: array[maxFourierSamples, Complex[float]]

# imgui style
proc knob*(center: Vector2, radius: float, `low`: float, `high`: float, increment: float, modifier: var float, thickness: float = 2.0) =
  if distance(getMousePosition(), center) <= radius:
    if isMouseButtonDown(Left):
      activeComponentTable[addr modifier] = true
      
  if isMouseButtonReleased(Left):
    activeComponentTable[addr modifier] = false

  var strokeColor = Black

  if activeComponentTable.contains(addr modifier) and activeComponentTable[addr modifier]:
    modifier += -getMouseDelta().y * increment
    modifier = clamp(modifier, `low`, `high`)
    setMouseCursor(MouseCursor.ResizeNs)
    strokeColor = SkyBlue

  drawRing(center, radius, radius + thickness, 0, 360, 120, strokeColor)
    #drawCircleLines(center.x.int32, center.y.int32, radius + 2, SkyBlue)

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

proc drawWavesToRect*(r: Rectangle, wavelengths: float) =
  let dt = wavelengths/(getScreenWidth().toFloat()*baseFreq)

  proc drawSampleToRect(sample: float, frameIdx: float) =
    #echo sample
    let sampleY = remap(sample, -1.0, 1.0, r.height, r.y)
    drawPixel(Vector2(x: r.x + frameIdx, y: sampleY), Red)

  runSampler(r.width.Natural, dt, drawSampleToRect)

proc drawFrequenciesToRect*(r: Rectangle, bands: Natural, showReflection: bool = false, stretch: float = 1.0) =
  var totalBands = 0
  if showReflection:
    assert(bands < maxFourierSamples) # must be a power of 2
    totalBands = bands
  else:
    assert(bands * 2 < maxFourierSamples) # must be a power of 2
    totalBands = bands * 2
  let dt = 1/(bands)

  proc collectSamples(sample: float, frameIdx: float) =
    samples[frameIdx.Natural] = sample

  runSampler(totalBands, dt, collectSamples)

  fft(samples, frequencies, totalBands)

  let rw: float = r.width / bands.toFloat()

  for i in 0..<bands:
    let freq = clamp(
      stretch * r.height * 
      (frequencies[i].abs() / totalBands.toFloat()), 
      0, r.height)
    drawRectangle(Vector2(x: i.toFloat() * rw, y: r.height - freq), Vector2(x: rw, y: freq), Green)

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
