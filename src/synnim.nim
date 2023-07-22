import raylib, std/[math, strformat, times]
import "synth.nim"
import "gui.nim"

const
  screenWidth = 800
  screenHeight = 450
  postShaderStr = staticRead("../assets/shaders/post.fs")

proc main =
  # Initialization
  # --------------------------------------------------------------------------------------
  setConfigFlags(flags(Msaa4xHint, WindowResizable)) # window config flags
  initWindow(screenWidth, screenHeight, "Synnim")
  defer: closeWindow() # Close window and OpenGL context
  let postShader = loadShaderFromMemory("", postShaderStr)
  let screenRect = Rectangle(x: 0, y: 0, width: screenWidth, height: screenHeight)
  let backframe = loadRenderTexture(screenWidth, screenHeight)
  setTextureFilter(backframe.texture, TextureFilter.Bilinear)
  var mySynth = new Synth
  mySynth.init()
  const dftRect: Rectangle = Rectangle(x: 600.0, y: 350.0, width: 200.0, height: 100.0)
  #let config: Flags[ConfigFlags] = Flags(WindowResizable)
  #setConfigFlags(WindowResizable)

  setTargetFPS(60) # Set our game to run at 30 frames-per-second
  # --------------------------------------------------------------------------------------
  # Main game loop
  while not windowShouldClose(): # Detect window close button or ESC key
    setMouseCursor(MouseCursor.Default)
    mySynth.handleInput()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    textureMode(backframe):
      clearBackground(RayWhite)
      drawWavesToRect(screenRect, 5)
      drawFrequenciesToRect(screenRect, 512)
      drawFps(0, 0)
      knob(Vector2(x: 10, y: 20), 10.0, 0.0, 1.0, 0.01, masterVolume)
      knob(Vector2(x: 100, y: 100), 10.0, 0.0, 1.0, 0.01, mySynth.filters[0].alpha)
      knob(Vector2(x: 130, y: 100), 10.0, 0.0, 1.0, 0.01, mySynth.filters[1].alpha)
      knob(Vector2(x: 50, y: 50), 30.0, -12.0, 12.0, 0.01, mySynth.tonalOffset)
      drawText(&"Active notes: {mySynth.activeNotes.len}", 300, 20, 10, Red)
      drawText(&"t: {globalt}", 300, 40, 10, Black)
    drawing():
      shaderMode(postShader):
        drawTexture(backframe.texture, Vector2(x: 0.0, y: 0.0), White)
    # ------------------------------------------------------------------------------------

main()