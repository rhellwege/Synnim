import raylib, std/[math, strformat, times, random]
import raymath
import locks

when compileoption("profiler"):
  import nimprof

when defined(windows): # do not include windows functions that collide with the raylib namespace
  {.localPassc: "-DNODRAWTEXT".} # TODO: Apply patch to raylib.h that adds #undef LoadImage on install

# TODO: add LFO's to oscillators
# TODO: add instrument type, and have constants that define oscillators and envelopes
# TODO: add filters (requires fft)
# TODO: add other effects like chorus, reverb, distortion, ...
# TODO: add draw and update functions that accept a rectangle to adaptively draw a representation of controls to the screen

type
  Hz* = float
  Semitone* = float
  Note = object
    id: Natural # used to delete itself
    tone: Semitone = 0
    onTime: float = 0
    offTime: float = 0
    velocity: float = 0
    active: bool = true
  EnvelopeADSR* = object
    attackTime*: float = 0
    decayTime*: float = 0
    releaseTime*: float = 0
    sustainVolume*: float = 1
    attackVolume*: float = 1
  OscillatorSampler* = proc(t: float, f: Hz): float
  Oscillator* =  object
    sampler*: OscillatorSampler
    freqOffset*: Hz = 0.0
    tonalOffset*: Semitone = 0.0
    timeOffset*: float = 0
    volume*: float = 1.0
    envelope*: EnvelopeADSR
  Synth* = object
    freqOffset*: Hz = 0
    volume*: float = 0
    oscillators*: seq[Oscillator] = @[]
    envelope*: EnvelopeADSR # this is the master envelope
    activeNotes: seq[Note] = @[]
    
# private constants
const
  sampleRate = 44100 # Hz
  maxSamplesPerUpdate = 4096
  masterVolume = 1.0
  tonalSystem = 12      # 12 semitone system
  tonalroot2 = pow(2.0, 1.0 / tonalSystem.float)
  baseFreq: Hz = 261.63 # middle C

# static variables
var
  globalt: float = 0
  stream: AudioStream
  synths: seq[ref Synth]
  audioMutex: Lock
  recording: bool
  captureBuffer: seq[int16]
  # outputwave has to have a global lifetime since =destroy calls unloadWave which frees the data pointer (captureBuffer)
  outputWave: Wave = Wave(sampleSize: 16, sampleRate: sampleRate, channels: 1, frameCount: uint32 captureBuffer.len(), data: nil)

converter toFreq(s: Semitone): Hz =
  return Hz baseFreq * pow(tonalroot2, s)

proc getEnvelopeVolume(n: var Note, e: EnvelopeADSR): float = # this may mark the note for deletion
  let curTime = cpuTime()
  let sinceOn = curTime - n.onTime
  if n.onTime > n.offTime: # the user is holding the note
    if sinceOn <= e.attackTime:
      return remap(sinceOn, 0.0, e.attackTime, 0.0, e.attackVolume)
    elif sinceOn <= e.attackTime + e.decayTime:
      return remap(sinceOn - e.attackTime, 0.0, e.decayTime, e.attackVolume, e.sustainVolume)
    else:
      #if e.sustainAmplitude == 0:
        #n.active = false
      return e.sustainVolume
  else:
    let sinceOff = curTime - n.offTime
    if sinceOff <= e.releaseTime:
      var startVolume = e.sustainVolume
      if sinceOn <= e.attackTime:
        startVolume = remap(sinceOn, 0.0, e.attackTime, 0.0, e.attackVolume)
      elif sinceOn <= e.attackTime + e.decayTime:
        startVolume = remap(sinceOn - e.attackTime, 0.0, e.decayTime, e.attackVolume, e.sustainVolume)
      #echo startVolume
      return remap(sinceOff, 0.0, e.releaseTime, startVolume, 0.0)
    else:
      n.active = false
      return 0.0

proc finalSample(s: ref Synth): float =
  var noteCount = 0
  for osc in s.oscillators:
    for note in s.activeNotes.mitems():
      if note.active: # TODO: replace this line with a pass to an envelope and multiply that with osc
        inc noteCount
        let envelopeVolume = note.getEnvelopeVolume(osc.envelope) # TODO: figure out master envelope vs envelope per oscillator
        let finalFrequency = (note.tone + osc.tonalOffset).toFreq() + osc.freqOffset
        result += osc.volume * envelopeVolume * osc.sampler(globalt, finalFrequency)
  result /= noteCount.toFloat()
  result /= s.oscillators.len.toFloat()
  result *= s.volume # apply synth volume
  # cleanup the notes seq
  while s.activeNotes.len > 0 and  not s.activeNotes[^1].active:
    discard s.activeNotes.pop()

proc allSynthFinalSamples(): float =
  for syn in synths:
    result += syn.finalSample()
  result /= synths.len.toFloat()
  result *= masterVolume # apply master volume
  result = clamp(result, -1.0, 1.0)

# where the magic happens: fills the audio device's buffer with our synth sample every time it requests new information
proc audioInputCallback(buffer: pointer; frames: uint32) {.cdecl.} =
  const dt = 1/sampleRate.float
  let arr = cast[ptr UncheckedArray[int16]](buffer)
  withLock(audioMutex): # this may introduce latency, might be better to lock each note processing
    for i in 0..<frames:
      let bits = int16(high(int16).toFloat()*(allSynthFinalSamples()))
      arr[i] = bits 
      if recording:
        captureBuffer.add(bits)
      globalt += dt
      if globalt > 2*PI*baseFreq: globalt -= 2*PI*baseFreq # might be a problem
          
proc oscSine(t: float, f: Hz): float =
  result = sin(2*PI*f*t)

proc oscTriangle(t: float, f: Hz): float =
  result = arcsin(sin(2*PI*f*t))

proc oscSquare(t: float, f: Hz): float =
  result = sin(2*PI*f*t)
  result = if result < 0.5: -1.0 else: 1.0

proc oscSawtooth(t: float, f: Hz): float =
  result = (2*t*f mod 2.0) - 1.0

proc oscNoise(t: float, f: Hz): float =
  result = rand(2.0) - 1.0

# public interface
proc init*(s: ref Synth) =
  if not isAudioDeviceReady():
    initAudioDevice()
    setAudioStreamBufferSizeDefault(maxSamplesPerUpdate)
  #s.oscillators.add(Oscilator(sampler: oscSine, envelope: EnvelopeADSR(attackTime: 0.1, attackAmplitude: 1.0, decayTime: 0.2, sustainAmplitude: 0.7, releaseTime: 1.0)))
  #s.oscillators.add(Oscillator(sampler: oscNoise, envelope: EnvelopeADSR(attackTime: 0.02, attackAmplitude: 1.0, decayTime: 0.1, sustainAmplitude: 0.0, releaseTime: 0.0)))
  s.oscillators.add(Oscillator(sampler: oscSine, envelope: EnvelopeADSR(attackTime: 100.0, attackVolume: 1.0, decayTime: 0.0, sustainVolume: 1.0, releaseTime: 100.0)))
  s.oscillators.add(Oscillator(sampler: oscSquare, tonalOffset: 12.0, envelope: EnvelopeADSR(attackTime: 100.0, attackVolume: 1.0, decayTime: 0.0, sustainVolume: 1.0, releaseTime: 1.0)))
  s.volume = masterVolume
  initLock audioMutex
  # Init raw audio stream (sample rate: 44100, sample size: 16bit-short, channels: 1-mono)
  if not stream.isAudioStreamReady:
    stream = loadAudioStream(sampleRate, 16, 1)
    stream.setAudioStreamCallback(audioInputCallback)
  if not stream.isAudioStreamPlaying:
    playAudioStream(stream)
  synths.add(s)

proc startRecording*() =
  echo "started recording"
  withLock(audioMutex):
    recording = true

proc stopRecording*() =
  withLock(audioMutex):
    recording = false
    outputWave.data = captureBuffer[0].addr
    let micros = now().format("ffffff")
    if not exportWave(outputWave, &"{micros}.wav"):
      echo "ERROR: could not export wave"
    outputWave.data = nil
    captureBuffer.reset()

# TODO: abstract away the id to the user
proc noteOn*(s: ref Synth; tone: Semitone; velocity: float = 1.0): Natural = 
  echo &"activating note with id: {s.activeNotes.len}, and tone of: {tone}"
  withLock(audioMutex):
    echo "got past lock after note on..."
    result = s.activeNotes.len
    s.activeNotes.add(Note(id: result, velocity: velocity, tone: tone,
        onTime: cpuTime(), offTime: 0))
    echo &"sent note: {s.activeNotes[^1]}"

proc noteOff*(s: ref Synth, id: Natural) =
  withLock(audioMutex):
    s.activeNotes[id].offTime = cpuTime()
  echo &"turned off noteid {id}"
