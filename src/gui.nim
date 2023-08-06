import raylib, raymath, math, tables, complex, os, strformat
import "synth.nim"
import "signal.nim"
import "raygui.nim"

# may need to #define RAYGUI_IMPLEMENTATION

{.emit: """/*INCLUDESECTION*/
#define RAYGUI_IMPLEMENTATION
""".}

when not defined(emscripten):
  {.passC: "-DRAYGUI_WINDOWBOX_STATUSBAR_HEIGHT=24".}
  var windowDragged = false
  const rayguiWindowBoxStatusBarHeight = 24
  proc getWindowBoxStatusBarRect(): Rectangle {.inline.} =
    return Rectangle(x: 0, y: 0, width: getScreenWidth().toFloat(), height: rayguiWindowBoxStatusBarHeight)
  proc getWindowBodyRect*(): Rectangle {.inline.} =
    result = Rectangle(x: 0, y: rayguiWindowBoxStatusBarHeight, width: getScreenWidth().toFloat(), height: getScreenHeight().toFloat() - rayguiWindowBoxStatusBarHeight)

# TODO: implement knob the way raygui does it with the context and the collisions and is dragged

const
  maxFourierSamples: Natural = 2048
  projectDir = currentSourcePath().parentDir().parentDir()
  fontsDir = projectDir / "resources/fonts"
  stylesDir = projectDir / "resources/styles"
  patchesDir = projectDir / "resources/patches"
  guiStyle = stylesDir / "bluish.rgs"
  postShaderStr = staticRead("../resources/shaders/post.fs")
  waveShaderStr = staticRead("../resources/shaders/wave_visualizer.fs")
  numSamples: int = 512
  widgetPadding: float = 8.0 # its the responsibility of the caller to provide padding, not the callee

var
  activeSampler = Sampler.Sine
  patchesFileState: GuiWindowFileDialogState # for the file dialog
  exitWindow: bool = false
  dragWindowPanOffset: Vector2
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
  waveTexture: RenderTexture
  samplesTexture: RenderTexture2D # 512 x 2 texture. first row is raw sample data, second row is fft frequencies
  maxFreqAmplitude: float = 0.0
  waveShader: Shader
  waveSamplesLoc: ShaderLocation
  wavetLoc: ShaderLocation
  waveResolutionLoc: ShaderLocation
  wavePrimaryColorLoc: ShaderLocation
  waveSecondaryColorLoc: ShaderLocation

proc initGui*(screenWidth: int32; screenHeight: int32; title: string) =
  let 
    primaryColor = getColor(guiGetStyle(Default, BorderColorPressed).uint32)
    secondaryColor = getColor(guiGetStyle(Default, BaseColorNormal).uint32)
  setConfigFlags(flags(Msaa4xHint, WindowUndecorated)) # window config flags
  when not defined(emscripten):
    setTargetFPS(60)
  initWindow(screenWidth, screenHeight, title)
  patchesFileState = initGuiWindowFileDialog(patchesDir)
  patchesFileState.setFilterExt(".json;all")
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
  setShaderValue(waveShader, wavePrimaryColorLoc, Vector4(x: primaryColor.r.float / 255.0, y: primaryColor.g.float / 255.0, z: primaryColor.b.float / 255.0, w: primaryColor.a.float / 255.0))
  setShaderValue(waveShader, waveSecondaryColorLoc, Vector4(x: secondaryColor.r.float / 255.0, y: secondaryColor.g.float / 255.0, z: secondaryColor.b.float / 255.0, w: secondaryColor.a.float / 255.0))
  setTextureFilter(backframe.texture, TextureFilter.Bilinear)

proc drawKnob*(center: Vector2; radius: float; `low`: float; `high`: float; increment: float; modifier: var float) =
  var strokeColor = getColor(guiGetStyle(Default, BorderColorNormal).uint32)
  let 
    thickness = guiGetStyle(Default, BorderWidth).float
    lineColor = getColor(guiGetStyle(Default, BorderColorFocused).uint32)
    fillColor = getColor(guiGetStyle(Button, BaseColorNormal).uint32)

  if not guiIsLocked() and guiGetState() != StateDisabled:
    if checkCollisionPointCircle(getMousePosition(), center, radius):
      if isMouseButtonDown(Left):
        activeComponentTable[addr modifier] = true
      
    if isMouseButtonReleased(Left):
      activeComponentTable[addr modifier] = false
  
    if activeComponentTable.contains(addr modifier) and activeComponentTable[addr modifier]:
      modifier += -getMouseDelta().y * increment
      modifier = clamp(modifier, `low`, `high`)
      setMouseCursor(MouseCursor.ResizeNs)
      strokeColor = getColor(guiGetStyle(Default, BorderColorPressed).uint32)
  drawRing(center, radius, radius + thickness, 0, 360, 120, strokeColor)

  drawCircle(center, radius, fillColor)
  let angle = remap(modifier, `low`, `high`, PI/6, (2*PI)-(PI/6)) + (PI / 2)
  drawLine(center, center + Vector2(x: radius*cos(angle), y: radius*sin(angle)), lineColor)

proc updateSamples(n: Natural; wavelengths: float) =
  let dt = wavelengths/(numSamples.toFloat()*baseFreq)
  var maxAmp = 0.0
  
  proc collectWaveSample(sample: float; frameIdx: float) =
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

proc drawWaves*(bounds: Rectangle; wavelengths: float) =
  # updateSamplesTexture should've been called before this
  if not waveTexture.isRenderTextureReady():
    waveTexture = loadRenderTexture(bounds.size())
  setShaderValueV(waveShader, waveSamplesLoc, waveSamples)
  setShaderValue(waveShader, waveResolutionLoc, bounds.size())

  shaderMode(waveShader):
    drawTexture(waveTexture.texture, bounds.pos(), White)

proc drawFrequencies*(bounds: Rectangle; bands: Natural; showReflection: bool = false; stretch: float = 1.0) =
  var totalBands = 0
  if showReflection:
    assert(bands < maxFourierSamples) # must be a power of 2
    totalBands = bands
  else:
    assert(bands * 2 < maxFourierSamples) # must be a power of 2
    totalBands = bands * 2

  let rw: float = bounds.width / bands.toFloat()

  for i in 0..<bands:
    let freq = clamp(
      stretch * bounds.height * 
      (freqSamples[i] / totalBands.toFloat()), 
      0, bounds.height)
    drawRectangle(Vector2(x: bounds.x + i.toFloat() * rw, y: bounds.y + bounds.height - freq),
                  Vector2(x: rw, y: freq),
                  getColor(guiGetStyle(Default, BorderColorNormal).uint32))

proc drawEnvelope*(bounds: Rectangle; e: Envelope) =
  let totalTime = e.attackTime + e.decayTime + e.releaseTime
  # attack line
  let attackPixels = Vector2(x: (e.attackTime/totalTime)*bounds.width, y: (bounds.y + bounds.height) - (e.attackValue * bounds.height))
  drawLine(Vector2(x: bounds.x, y: bounds.y + bounds.height), attackPixels, Red)
  drawRectangleLines(bounds, 2.0, Red)
  discard

var editMode: bool = false
proc drawOscillator*(bounds: Rectangle; o: var Oscillator) =
  discard guiGroupBox(bounds, "oscillator")
  editMode = guiDropDownBoxEnum(bounds.ipos() + Rectangle(x: 10, y: 10, width: bounds.width - 20, height: 20), o.sampler, editMode)

var panelView: Rectangle
var scroll: Vector2
proc drawSynth*(bounds: Rectangle; s: ref Synth) =
  # discard guiGroupBox(bounds, "Synth")
  let nOsc = s.patch.oscillators.len()
  let w = if nOsc < 2: bounds.width / nOsc.toFloat() else: bounds.width / 2 
  let content = rwidth(w * nOsc.toFloat())
  discard guiScrollPanel(bounds, nil.cstring, content, scroll, panelView)
  scissorModeRect(bounds):
    for i, osc in s.patch.oscillators.mpairs():
      drawOscillator((scroll.rpos() + bounds.ipos() + rx(i.toFloat() * w) + rwidth(w) + rheight(bounds.height)).padding(widgetPadding), osc)

proc drawGui*(bounds: Rectangle; s: ref Synth) = # TODO: instead of passing in s pass in the static audio context
  setMouseCursor(MouseCursor.Default)
  s.handleInput()
  updateSamples(512, 5.0)
  drawing():
    textureMode(backframe): # should this go in gui.nim?
      clearBackground(White)
      when not defined(emscripten):
        exitWindow = guiWindowBox(getScreenRect(), windowTitle.cstring).bool
      drawFrequencies(bounds.ipos() + bounds.splitHeight().isize(), 512, stretch = 3.0)
      # drawWaves(bounds, 5)
      drawKnob(bounds.pos() + Vector2(x: 10, y: 20), 10.0, 0.0, 1.0, 0.01, s.patch.volume)
      drawKnob(bounds.pos() + Vector2(x: 100, y: 100), 10.0, 0.0, 1.0, 0.01, s.patch.filters[0].alpha)
      drawKnob(bounds.pos() + Vector2(x: 130, y: 100), 10.0, 0.0, 1.0, 0.01, s.patch.filters[1].alpha)
      drawKnob(bounds.pos() + Vector2(x: 50, y: 50), 30.0, -12.0, 12.0, 0.01, s.patch.tonalOffset)
      discard guiLabel(bounds.ipos() + Rectangle(x: 300, y: 20, width: 100, height: 10), cstring &"Active notes: {s.activeNotes.len}")
      discard guiLabel(bounds.ipos() + Rectangle(x: 300, y: 30, width: 100, height: 10), cstring &"t: {globalt}")
      discard guiLabel(bounds.ipos() + Rectangle(x: 300, y: 40, width: 200, height: 10), cstring &"mpos: {getMousePosition().repr}")
      discard guiLabel(bounds.ipos() + Rectangle(x: 300, y: 50, width: 200, height: 10), cstring &"mdelta: {getMouseDelta().repr}")
      discard guiLabel(bounds.ipos() + Rectangle(x: 300, y: 60, width: 200, height: 10), cstring &"wpos: {getWindowPosition().repr}")
      drawSynth((bounds.ipos() + ry(bounds.height/2).ipos() + bounds.splitHeight().isize()).padding(widgetPadding), s)
      discard guiComboBoxEnum(bounds.ipos() + Rectangle(x: 300, y: 200, width: 200, height: 150), activeSampler)
      let buttonBounds = bounds.ipos() + Rectangle(x: 500, y: 20, width: 100, height: 30)
      tooltip(buttonBounds, "Select a patch file to change instrument settings."):
        if guiButton(buttonBounds, "Open Patch"):
          patchesFileState.windowActive = true
      isolateGuiIf(patchesFileState.windowActive):
        patchesFileState.guiWindowFileDialog() # draw file dialog
      if patchesFileState.CancelFilePressed:
        patchesFileState.setDirPath(patchesDir)
        patchesFileState.CancelFilePressed = false
      elif patchesFileState.SelectFilePressed:
        s.setPatch(patchesFileState.getFullPath())
        patchesFileState.setDirPath(patchesDir)
        patchesFileState.SelectFilePressed = false
    shaderMode(postShader):
      drawTexture(backframe.texture, Vector2(x: 0.0, y: 0.0), White)
    drawFps(bounds.pos().x.int32, bounds.pos().y.int32)

when defined(emscripten):
  var globalSynth: ref Synth
  proc updateDrawFrame() {.cdecl.} =
    drawGui(getScreenRect(), globalSynth)
  
proc runGui*(s: ref Synth) =
  when defined(emscripten):
    globalSynth = s
    emscriptenSetMainLoop(updateDrawFrame, 0, 1)
  else:
    while not exitWindow and not windowShouldClose(): # Detect window close button or ESC key
      if not windowDragged and checkCollisionPointRec(getMousePosition(), getWindowBoxStatusBarRect()) and isMouseButtonPressed(Left):
        windowDragged = true
        dragWindowPanOffset = getMousePosition()
      if windowDragged:
        let newPos = getWindowPosition() + (getMousePosition() - dragWindowPanOffset)
        setWindowPosition(newPos)
        if isMouseButtonReleased(Left):
          windowDragged = false
      drawGui(getWindowBodyRect(), s)
    closeWindow()