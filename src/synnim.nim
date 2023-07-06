import raylib, std/[math, strformat, times]
import "synth.nim"

const
  screenWidth = 800
  screenHeight = 450

proc main =
  # Initialization
  # --------------------------------------------------------------------------------------
  initWindow(screenWidth, screenHeight, "Synnim")
  defer: closeWindow() # Close window and OpenGL context
  var mySynth = new Synth
  mySynth.init()
  #adefer: closeAudioDevice() # TODO refactor in synth.nim

  setTargetFPS(60) # Set our game to run at 30 frames-per-second
  # --------------------------------------------------------------------------------------
  # Main game loop
  while not windowShouldClose(): # Detect window close button or ESC key
    if isKeyPressed(A):
      mySynth.noteOn(3.Semitone)
    if isKeyReleased(A):
      mySynth.noteOff()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    drawing():
      clearBackground(RayWhite)
    # ------------------------------------------------------------------------------------

main()