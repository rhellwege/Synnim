import raylib, std/[math, strformat, times]
import locks

when defined(windows): # do not include windows functions that collide with the raylib namespace
  {.localPassc: "-DNODRAWTEXT".} # TODO: Apply patch to raylib.h that adds #undef LoadImage on install

type
  Hz* = float
  Semitone* = range[0..88]
  Note = object
    id: Natural # used to delete itself
    freq: Hz = 0
    onTime: float = 0
    offTime: float = 0
    velocity: float = 0
    active: bool = true
  OscilatorType = enum
    Sine
    Triangle
    Square
    Sawtooth
    Noise
    None
  Oscilator = proc(t: float, f: Hz): float {.noSideEffect.}
  EnvelopeADSR = object
    attackTime: float
    decayTime: float
    releaseTime: float
    sustainAmplitude: float
    initialAmplitude: float
  Synth* = object # TODO: add freqs as a seq so we can play many notes at once
                  #freq*: Hz = 0
    freqOffset*: Hz = 0
    volume*: float = 0
    oscillators*: seq[Oscilator]
    envelopes*: seq[EnvelopeADSR]
    activeNotes: seq[Note] # when turn off id is requested, put zeroes in the note, unless its the last in the array to get it a unique id
    

# private constants
const
  sampleRate = 44100   # Hz
  maxSamplesPerUpdate = 4096
  maxSamples = 512
  masterVolume = 1.0
  tonalSystem = 12     # 12 semitone system
  tonalroot2 = pow(2.0, 1.0 / tonalSystem.float)
  baseFreq: Hz = 110.0 # A2

# global variables
var
  globalt: float = 0
  stream: AudioStream
  synths: seq[ref Synth]
  audioMutex: Lock

converter toFreq(s: Semitone): Hz =
  return Hz baseFreq * pow(tonalroot2, s.toFloat())

proc getEnvelopeVolume(e: EnvelopeADSR, n: Note, t: float): float =
  0

proc finalAmplitude(s: ref Synth): float {.thread.} =
  let curTime = cpuTime()
  var noteCount = 0
  for osc in s.oscillators:
    for i, note in s.activeNotes.pairs():
      if note.offTime < note.onTime: # TODO: replace this line with a pass to an envelope and multiply that with osc
        inc noteCount
        result += osc(globalt + (0.01 * i.toFloat()), note.freq)
  result /= noteCount.toFloat()
  result *= s.volume
  while s.activeNotes.len > 0 and s.activeNotes[^1].onTime < s.activeNotes[^1].offTime and curTime > s.activeNotes[
      ^1].offTime:
    discard s.activeNotes.pop()
    
  
  if abs(result) > 1.0:
    echo result
  result.clamp(-1, 1)

# private procs
proc audioInputCallback(buffer: pointer; frames: uint32) {.cdecl.} =
  # send data to the sound card whenever it needs it
  const dt = 1/sampleRate.float
  let arr = cast[ptr UncheckedArray[int16]](buffer)
  withLock(audioMutex):
    for i in 0..<frames:
      arr[i] = 0
      for syn in synths:
        arr[i] += int16(high(int16).toFloat()*syn.finalAmplitude())
      globalt += dt
      if globalt > 2*PI*baseFreq: globalt -=
          2*PI*baseFreq # TODO: find a different value to avoid pops. this is necessary to avoid floating point imprecision

proc oscSine(t: float, f: Hz): float {.noSideEffect.} =
  result = sin(2*PI*f*t)

proc oscSquare(t: float, f: Hz): float {.noSideEffect.} =
  result = sin(2*PI*f*t)
  result = if result < 0.5: -1.0 else: 1.0

# public interface
proc init*(s: ref Synth) =
  initAudioDevice()
  setAudioStreamBufferSizeDefault(maxSamplesPerUpdate)
  s.oscillators.add(oscSine)
  s.volume = masterVolume
  initLock audioMutex
  #s.freq = 0
  #s.oscillators.add(oscSquare)
  # Init raw audio stream (sample rate: 44100, sample size: 16bit-short, channels: 1-mono)
  if not stream.isAudioStreamReady:
    stream = loadAudioStream(sampleRate, 16, 1)
    stream.setAudioStreamCallback(audioInputCallback)
  if not stream.isAudioStreamPlaying:
    playAudioStream(stream)
  synths.add(s)

proc noteOn*(s: ref Synth; tone: Semitone;
    velocity: float = 1.0): Natural = # TODO: use the semitone as a key to the notes seq somehow
  echo "main thread id: ", getThreadId()
  echo &"activating note with id: {s.activeNotes.len}, and tone of: {tone}"
  withLock(audioMutex):
    echo "got past lock after note on..."
    result = s.activeNotes.len
    s.activeNotes.add(Note(id: result, velocity: velocity, freq: tone.toFreq(),
        onTime: cpuTime(), offTime: 0))

proc noteOff*(s: ref Synth, id: Natural) =
  withLock(audioMutex):
    s.activeNotes[id].offTime = cpuTime()
  echo &"turned off noteid {id}"
