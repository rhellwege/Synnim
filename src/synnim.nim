import raylib, std/[math, strformat, times]
import "synth.nim"
import "gui.nim"

#TODO: use uniforms in a shader to draw frequencies and waves, drawPixel is VERY slow in webgl
# file dialogues
#https://stackoverflow.com/questions/2897619/using-html5-javascript-to-generate-and-save-a-file
#C:\Users\rhell\.local\tinyfiledialog
  
proc main =
  initGui(800, 800, "Synnim")
  var mySynth = new Synth
  mySynth.init()
  mySynth.runGui()
main()