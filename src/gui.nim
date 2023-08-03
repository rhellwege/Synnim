import raylib, raymath, math, tables, locks, complex, os, strformat
import "synth.nim"
import "signal.nim"
import "raygui.nim"

# type
#   Widget = object
#     id: Natural
#     parent: Natural = 0
#     children: seq[Natural] = @[]
#     bounds: Rectangle
#     shown: bool

# # Global variables:
# var
#   widgets: seq[Widget] = @[]


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
  postShaderStr = staticRead("../resources/shaders/post.fs")
  waveShaderStr = staticRead("../resources/shaders/wave_visualizer.fs")
  numSamples: int = 512

var
  exitWindow: bool = false
  windowTitle: string
  waveSamples: array[numSamples, float32] # hack the precision
  freqSamples: array[numSamples, float]
  activeComponentTable: Table[pointer, bool]
  samples: array[maxFourierSamples, float]
  frequencies: array[maxFourierSamples, Complex[float]]
  guiFont: Font
  # Textures / Shaders:
  backframe: RenderTexture
  postShader: Shader
  #mySynth: ref Synth
  waveTexture: RenderTexture
  samplesTexture: RenderTexture2D # 512 x 2 texture. first row is raw sample data, second row is fft frequencies
  maxFreqAmplitude: float = 0.0
  waveShader: Shader
  waveSamplesLoc: ShaderLocation
  wavetLoc: ShaderLocation
  waveResolutionLoc: ShaderLocation
  wavePrimaryColorLoc: ShaderLocation
  waveSecondaryColorLoc: ShaderLocation

proc initGui*(screenWidth: Natural, screenHeight: Natural, title: string) =
  setConfigFlags(flags(Msaa4xHint, WindowResizable, WindowUndecorated)) # window config flags
  initWindow(screenWidth.int32, screenHeight.int32, title)
  windowTitle = title
  guiLoadStyle(guiStyle)
  backframe  = loadRenderTexture(getScreenWidth(), getScreenHeight())
  postShader = loadShaderFromMemory("", postShaderStr)
  waveShader = loadShaderFromMemory("", waveShaderStr)
  waveResolutionLoc     = getShaderLocation(waveShader, "resolution")
  wavetLoc              = getShaderLocation(waveShader, "t")
  waveSamplesLoc        = getShaderLocation(waveShader, "samples")
  wavePrimaryColorLoc   = getShaderLocation(waveShader, "primaryColor")
  waveSecondaryColorLoc = getShaderLocation(waveShader, "secondaryColor")
  let primaryColor = getColor(guiGetStyle(GuiControl.Default.int32, GuiControlProperty.BorderColorPressed.int32).uint32)
  let secondaryColor = getColor(guiGetStyle(GuiControl.Default.int32, GuiControlProperty.BaseColorNormal.int32).uint32)
  setShaderValue(waveShader, wavePrimaryColorLoc, Vector4(x: primaryColor.r.float / 255.0, y: primaryColor.g.float / 255.0, z: primaryColor.b.float / 255.0, w: primaryColor.a.float / 255.0))
  setShaderValue(waveShader, waveSecondaryColorLoc, Vector4(x: secondaryColor.r.float / 255.0, y: secondaryColor.g.float / 255.0, z: secondaryColor.b.float / 255.0, w: secondaryColor.a.float / 255.0))
  setTextureFilter(backframe.texture, TextureFilter.Bilinear)

proc getScreenRect*(): Rectangle {.inline.} = 
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

proc updateSamples(n: Natural, wavelengths: float) =
  let dt = wavelengths/(numSamples.toFloat()*baseFreq)
  var maxAmp = 0.0
  
  proc collectWaveSample(sample: float, frameIdx: float) =
    samples[frameIdx.toInt()] = sample
    let s = remap(sample, -1.0, 1.0, 0.0, 255.0)
    
    waveSamples[frameIdx.toInt()] = s

  runSampler(numSamples, dt, collectWaveSample) # this might be kinda dumb
  fft(samples, frequencies, numSamples)
  for i in 0..<numSamples:
    maxAmp = max(frequencies[i].abs(), maxAmp)
  
  for i in 0..<numSamples:
    let s = remap(frequencies[i].abs(), 0.0, maxAmp, 0.0, 255.0)
    freqSamples[i] = s


proc drawWaves*(r: Rectangle, wavelengths: float) =
  # updateSamplesTexture should've been called before this
  if not waveTexture.isRenderTextureReady():
    waveTexture = loadRenderTexture(r.width.int32, r.height.int32)
  setShaderValueV(waveShader, waveSamplesLoc, waveSamples)
  setShaderValue(waveShader, waveResolutionLoc, Vector2(x: r.width, y: r.height))

  shaderMode(waveShader):
    drawTexture(waveTexture.texture, Vector2(x: r.x, y: r.y), White)

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
  s.handleInput()
  #updateSamples(512, 5.0)
  drawing():
    textureMode(backframe): # should this go in gui.nim?
      clearBackground(White)
      when not defined(emscripten):
        exitWindow = guiWindowBox(getScreenRect(), windowTitle).bool
      drawFrequencies(getScreenRect(), 512, stretch = 3.0)
      drawKnob(Vector2(x: 10, y: 20), 10.0, 0.0, 1.0, 0.01, s.patch.volume)
      drawKnob(Vector2(x: 100, y: 100), 10.0, 0.0, 1.0, 0.01, s.patch.filters[0].alpha)
      drawKnob(Vector2(x: 130, y: 100), 10.0, 0.0, 1.0, 0.01, s.patch.filters[1].alpha)
      drawKnob(Vector2(x: 50, y: 50), 30.0, -12.0, 12.0, 0.01, s.patch.tonalOffset)
      discard guiLabel(Rectangle(x: 300, y: 20, width: 50, height: 10), cstring &"Active notes: {s.activeNotes.len}")
      discard guiLabel(Rectangle(x: 300, y: 30, width: 50, height: 10), cstring &"t: {globalt}")
    shaderMode(postShader):
      drawTexture(backframe.texture, Vector2(x: 0.0, y: 0.0), White)
    drawFps(0, 0)

proc runGui*(s: ref Synth) =
  when defined(emscripten):
    proc updateDrawFrame() =
      drawGui(s)
    emscriptenSetMainLoop(updateDrawFrame, 0, 1)
  else:
    while not exitWindow and not windowShouldClose(): # Detect window close button or ESC key
      drawGui(s)
    closeWindow()