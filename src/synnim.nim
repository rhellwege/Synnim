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

  setTargetFPS(60) # Set our game to run at 30 frames-per-second
  # --------------------------------------------------------------------------------------
  # Main game loop
  var keys: array[char, int]
  while not windowShouldClose(): # Detect window close button or ESC key
    if isKeyPressed(One):
      startRecording()
    elif isKeyPressed(Two):
      stopRecording()
    for i, c in "ZSXDCVGBHNJM,".pairs():
      if c == ',':
        if isKeyPressed(Comma):
          keys[c] =  mySynth.noteOn(12)
        if isKeyReleased(Comma):
          mySynth.noteOff(keys[c])
      else:
        if isKeyPressed(c.ord.KeyBoardKey):
          keys[c] = mySynth.noteOn(i.Semitone)
          echo &"activated: {keys[c]} {i.Semitone}"
        if isKeyReleased(c.ord.KeyBoardKey):
          mySynth.noteOff(keys[c])
    
    #mySynth.noteOff()
    # ------------------------------------------------------------------------------------
    # Draw
    # ------------------------------------------------------------------------------------
    drawing():
      clearBackground(RayWhite)
    # ------------------------------------------------------------------------------------

main()