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
  var keys: array[char, int]
  while not windowShouldClose(): # Detect window close button or ESC key
    
    for i, c in "ZSXDCVGBHNJM".pairs():
      if isKeyPressed(c.ord.KeyBoardKey):
        keys[c] = mySynth.noteOn(i.Semitone)
      if isKeyReleased(c.ord.KeyBoardKey):
        mySynth.noteOff(keys[c])
        keys[c] = -1
    
    #mySynth.noteOff()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    drawing():
      clearBackground(RayWhite)
    # ------------------------------------------------------------------------------------

main()