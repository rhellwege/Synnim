import raylib, raymath, math, tables, locks, complex, os, strformat
import "synth.nim"
import "signal.nim"
import "raygui.nim"

# TODO: use raygui
# TODO: allow user to control synth with midi
# TODO: allow user to play a midi recording

# may need to #define RAYGUI_IMPLEMENTATION


{.emit: """/*INCLUDESECTION*/
#define RAYGUI_IMPLEMENTATION
""".}

# TODO: implement knob the way raygui does it with the context and the collisions and is dragged

const
  maxFourierSamples: Natural = 2048
  projectDir = currentSourcePath().parentDir().parentDir()
  fontsDir = projectDir / "resources/fonts"
  stylesDir = projectDir / "resources/styles"
  guiStyle = stylesDir / "cherry.rgs"

var
  activeComponentTable: Table[pointer, bool]
  samples: array[maxFourierSamples, float]
  frequencies: array[maxFourierSamples, Complex[float]]
  guiFont: Font

proc initGui*() =
  #guiFont = loadFont(fontsDir / "Alegreya-Regular.ttf")
  #setTextureFilter(guiFont.texture, Bilinear)
  #guiSetFont(guiFont)
  guiLoadStyle(guiStyle)
 
proc getRenderRect*(): Rectangle {.inline.} = 
  result = Rectangle(x: 0, y: 0, width: getScreenWidth().toFloat(), height: getScreenHeight().toFloat())

proc drawKnob*(center: Vector2, radius: float, `low`: float, `high`: float, increment: float, modifier: var float, thickness: float = 2.0) =
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

proc drawWaves*(r: Rectangle, wavelengths: float) =
  let dt = wavelengths/(getScreenWidth().toFloat()*baseFreq)

  proc drawSample(sample: float, frameIdx: float) =
    #echo sample
    let sampleY = remap(sample, -1.0, 1.0, r.height, r.y)
    drawPixel(Vector2(x: r.x + frameIdx, y: sampleY), getColor(guiGetStyle(GuiControl.Default.int32, GuiControlProperty.BorderColorPressed.int32).uint32))

  runSampler(r.width.Natural, dt, drawSample)

proc drawFrequencies*(r: Rectangle, bands: Natural, showReflection: bool = false, stretch: float = 1.0) =
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
    drawRectangle(Vector2(x: i.toFloat() * rw, y: r.height - freq), Vector2(x: rw, y: freq), getColor(guiGetStyle(GuiControl.Default.int32, GuiControlProperty.BorderColorNormal.int32).uint32))

proc drawEnvelope*(e: Envelope, r: Rectangle) =
  let totalTime = e.attackTime + e.decayTime + e.releaseTime
  # attack line
  let attackPixels = Vector2(x: (e.attackTime/totalTime)*r.width, y: (r.y + r.height) - (e.attackValue * r.height))
  drawLine(Vector2(x: r.x, y: r.y + r.height), attackPixels, Red)
  drawRectangleLines(r, 2.0, Red)
  discard

proc drawOscillator*(o: Oscillator, r: Rectangle) =
  discard

proc drawSynth*(s: Synth, r: Rectangle) =
  discard

proc drawGui*(s: ref Synth) = # TODO: instead of passing in s pass in the static audio context
  #guiGetStyle()
  #clearBackground(RayWhite)
  discard guiPanel(getRenderRect(), "main")
  drawWaves(getRenderRect(), 5)
  drawFrequencies(getRenderRect(), 512, stretch = 3.0)
  drawKnob(Vector2(x: 10, y: 20), 10.0, 0.0, 1.0, 0.01, s.patch.volume)
  drawKnob(Vector2(x: 100, y: 100), 10.0, 0.0, 1.0, 0.01, s.patch.filters[0].alpha)
  drawKnob(Vector2(x: 130, y: 100), 10.0, 0.0, 1.0, 0.01, s.patch.filters[1].alpha)
  drawKnob(Vector2(x: 50, y: 50), 30.0, -12.0, 12.0, 0.01, s.patch.tonalOffset)
  discard guiLabel(Rectangle(x: 300, y: 20, width: 50, height: 10), cstring &"Active notes: {s.activeNotes.len}")
  discard guiLabel(Rectangle(x: 300, y: 30, width: 50, height: 10), cstring &"t: {globalt}")
  drawFps(0, 0)