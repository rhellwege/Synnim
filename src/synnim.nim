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
  initGui()
  defer: closeWindow() # Close window and OpenGL context
  let postShader = loadShaderFromMemory("", postShaderStr)
  let backframe = loadRenderTexture(screenWidth, screenHeight)
  setTextureFilter(backframe.texture, TextureFilter.Bilinear)
  var mySynth = new Synth
  mySynth.init()
  const dftRect: Rectangle = Rectangle(x: 600.0, y: 350.0, width: 200.0, height: 100.0)
  #let config: Flags[ConfigFlags] = Flags(WindowResizable)
  #setConfigFlags(WindowResizable)
  #setTargetFPS(60) # Set our game to run at 30 frames-per-second
  # --------------------------------------------------------------------------------------
  # Main game loop 
  while not windowShouldClose(): # Detect window close button or ESC key
    setMouseCursor(MouseCursor.Default)
    
    mySynth.handleInput()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    textureMode(backframe):
      drawGui(mySynth)
      #discard guiCheckBox(Rectangle(x: 50, y: 40, width: 20, height: 20), "test", testCheck)
    drawing():
      shaderMode(postShader):
        drawTexture(backframe.texture, Vector2(x: 0.0, y: 0.0), White)
    # ------------------------------------------------------------------------------------
main()