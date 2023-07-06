import raylib, std/[math, strformat, times]

type
  Hz* = float32
  Semitone* = Natural
  OscilatorType = enum
    Sine
    Triangle
    Square
    Sawtooth
    Noise
    None
  Oscilator = proc(t: float32, f: Hz): float32 {.noSideEffect.}
  EnvelopeADSR = object
    attackTime: float32
    decayTime: float32
    releaseTime: float32
    sustainAmplitude: float32
    initialAmplitude: float32
    triggerOnTime: float32
    triggerOffTime: float32
  Synth* = object
    freq*: Hz = 0
    volume*: float32 = 0
    oscillators*: seq[Oscilator]
    envelopes*: seq[EnvelopeADSR]

# private constants
const
  sampleRate = 44100
  maxSamplesPerUpdate = 4096
  maxSamples = 512
  masterVolume = 1.0
  twelthrooth2 = pow(2.0, 1.0 / 12.0)
  baseFreq: Hz = 110.0 # A2
  

# global variables
var
  globalt: float32 = 0
  stream: AudioStream
  synths: seq[ref Synth]

converter toFreq(s: Semitone): Hz =
    return Hz baseFreq * pow(twelthrooth2, s.toFloat())

proc finalAmplitude(s: ref Synth): float32 =
    for osc in s.oscillators:
        result += osc(globalt, s.freq)
    result *= s.volume
    
# private procs
proc audioInputCallback(buffer: pointer; frames: uint32) {.cdecl.} =
  # send data to the sound card whenever it needs it
  const dt = 1/sampleRate.float32
  let arr = cast[ptr UncheckedArray[int16]](buffer)
  for i in 0..<frames:
    arr[i] = 0
    for syn in synths:
        arr[i] += int16(high(int16).toFloat()*syn.finalAmplitude())
    globalt += dt
    #if globalt > 1: globalt -= 1

proc oscSine(t: float32, f: Hz): float32 {.noSideEffect.} =
    result = sin(2*PI*f*t)

proc oscSquare(t: float32, f: Hz): float32 {.noSideEffect.} =
    result = sin(2*PI*f*t)
    result = if result < 0.5: -1.0 else: 1.0

# public interface
proc init*(s: ref Synth) =
  initAudioDevice()
  setAudioStreamBufferSizeDefault(maxSamplesPerUpdate)
  s.oscillators.add(oscSine)
  s.volume = 0
  s.freq = 0
  #s.oscillators.add(oscSquare)
  # Init raw audio stream (sample rate: 44100, sample size: 16bit-short, channels: 1-mono)
  if not stream.isAudioStreamReady:
    stream = loadAudioStream(sampleRate, 16, 1)
    stream.setAudioStreamCallback(audioInputCallback)
  if not stream.isAudioStreamPlaying:
    playAudioStream(stream)
  synths.add(s)

proc noteOn*(s: ref Synth, freq: Hz, velocity: float32 = 1.0) =
    s.freq = freq
    s.volume = masterVolume*velocity
    echo s.freq, " ", s.volume

proc noteOn*(s: ref Synth, semi: Semitone, velocity: float32 = 1.0) =
    s.freq = toFreq(semi)
    s.volume = masterVolume*velocity
    echo s.freq, " ", s.volume

proc noteOff*(s: ref Synth) =
    s.volume = 0
    s.freq = 0
    echo "keyoff"