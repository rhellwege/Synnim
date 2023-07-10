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
  #let config: Flags[ConfigFlags] = Flags(WindowResizable)
  #setConfigFlags(WindowResizable)

  setTargetFPS(60) # Set our game to run at 30 frames-per-second
  # --------------------------------------------------------------------------------------
  # Main game loop
  var keys: array[char, int]
  while not windowShouldClose(): # Detect window close button or ESC key
    mySynth.handleInput()
    drawAnalyzerToRect(screenRect)
    drawFps(0, 0)
    knob(Vector2(x: 10, y: 20), 10.0, 0.0, 1.0, 0.1, masterVolume)
    knob(Vector2(x: 50, y: 50), 30.0, 0.0, 12.0, 0.1, mySynth.tonalOffset)
    drawText(&"Active notes: {mySynth.activeNotes.len}", 300, 20, 10, Red)
    #mySynth.noteOff()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    drawing():
      clearBackground(RayWhite)
    # ------------------------------------------------------------------------------------

main()