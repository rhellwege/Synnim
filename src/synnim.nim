import raylib, std/[math, strformat, times]
import "synth.nim"
import "gui.nim"

const
  screenWidth = 800
  screenHeight = 450

proc main =
  # Initialization
  # --------------------------------------------------------------------------------------
  initWindow(screenWidth, screenHeight, "Synnim")
  let screenRect = Rectangle(x: 0, y: 0, width: screenWidth, height: screenHeight)
  defer: closeWindow() # Close window and OpenGL context
  var mySynth = new Synth
  mySynth.init()

  setTargetFPS(60) # Set our game to run at 30 frames-per-second
  # --------------------------------------------------------------------------------------
  # Main game loop
  var keys: array[char, int]
  while not windowShouldClose(): # Detect window close button or ESC key
    mySynth.handleInput()
    drawAnalyzerToRect(screenRect)
    
    #mySynth.noteOff()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    drawing():
      clearBackground(RayWhite)
    # ------------------------------------------------------------------------------------

main()