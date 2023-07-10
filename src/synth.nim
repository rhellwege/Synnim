import raylib, std/[math, strformat, times, random]
import raymath
import locks

when compileoption("profiler"):
  import nimprof

when defined(windows): # do not include windows functions that collide with the raylib namespace
  {.localPassc: "-DNODRAWTEXT".} # TODO: Apply patch to raylib.h that adds #undef LoadImage on install

# TODO: refactor global variables to a context struct for readability
# TODO: add LFO's to oscillators
# TODO: add instrument type, and have constants that define oscillators and envelopes
# TODO: add filters (requires fft)
# TODO: add other effects like chorus, reverb, distortion, ...
# TODO: add draw and update functions that accept a rectangle to adaptively draw a representation of controls to the screen
# private constants
type
  Hz* = float
  Semitone* = float

const
  sampleRate = 44100 # Hz
  maxSamplesPerUpdate = 4096
  masterVolume = 0.5
  tonalSystem = 12      # 12 semitone system
  tonalroot2 = pow(2.0, 1.0 / tonalSystem.float)
  baseFreq: Hz = 110.0 # low A
  keyMapping: seq[KeyBoardKey] = @[Z, S, X, C, F, V, G, B, N, J, M, K, Comma, L, Period] # for input
  startRecordingKey: KeyBoardKey = One
  stopRecordingKey: KeyBoardKey = Two
  noteDeactivateThresh: float = 0.001
  maxSnapshotSamples = 256 * 256 * 256
  maxSampleHeight = 32_000

type
  Note = object
    #id: Natural # used to delete itself
    tone: Semitone = 0
    onTime: float = 0
    offTime: float = 0
    offVolume: float = 0
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
    noteIds: seq[seq[ptr Note]] = @[]
    activeNotes: seq[tuple[note: Note, oscillator: ptr Oscillator]] = @[]
    activeKeyIds: array[keyMapping.len, tuple[ids: tuple[startId: int, endId: int], held: bool]]

# static variables
var
  globalt: float = 0
  stream: AudioStream
  synths: seq[ref Synth]
  recording: bool = false
  audioMutex: Lock
  snapshotMutex: Lock
  recordBuffer: seq[int16]
  recordToSnapshot: bool = false
  snapshotBuffer: ptr UncheckedArray[int16]
  snapshotSize: Natural = 0
  snapshotIdx: Natural = 0
  outputWave: Wave = Wave(sampleSize: 16, sampleRate: sampleRate, channels: 1, data: nil)

converter toFreq*(s: Semitone): Hz =
  return Hz baseFreq * pow(tonalroot2, s)

func sampleToInt16*(sample: float): int16 =
  return int16(maxSampleHeight.toFloat()*sample)

func int16ToSample*(bits: int16): float =
  return bits.toFloat()/maxSampleHeight.toFloat()

proc applyEnvelope(n: var Note, e: EnvelopeADSR): float = # we need to change the structure of the oscilators and the notes
  let curTime = cpuTime()
  let sinceOn = curTime - n.onTime
  if n.onTime > n.offTime: # the user is holding the note
    if sinceOn <= e.attackTime:
      n.offVolume = remap(sinceOn, 0.0, e.attackTime, 0.0, e.attackVolume)
      return n.offVolume
    elif sinceOn <= e.attackTime + e.decayTime:
      n.offVolume = remap(sinceOn - e.attackTime, 0.0, e.decayTime, e.attackVolume, e.sustainVolume)
      return n.offVolume
    else:
      n.offVolume = e.sustainVolume
      return e.sustainVolume
  else:
    let sinceOff = curTime - n.offTime
    result = remap(sinceOff, 0.0, e.releaseTime, n.offVolume, 0.0)
    if sinceOff <= e.releaseTime and result > noteDeactivateThresh:
      return
    else:
      echo "deactivating note..."
      n.active = false
      return 0.0

proc finalSample(s: ref Synth): float =
  for note, osc in s.activeNotes.mitems():
    if note.active:
      let noteVolume = note.applyEnvelope(osc.envelope) * osc.volume
      let finalFrequency = (note.tone + osc.tonalOffset).toFreq() + osc.freqOffset
      result += noteVolume * osc.sampler(globalt, finalFrequency)
  result *= s.volume # apply synth volume
  #result = normalize(result, -1.0, 1.0)
  # cleanup the notes seq
  while s.activeNotes.len > 0 and not s.activeNotes[^1].note.active:
    discard s.activeNotes.pop()

proc allSynthFinalSamples(): float =
  for syn in synths:
    result += syn.finalSample()
  result *= masterVolume # apply master volume
  #result = normalize(result, -1.0, 1.0)

proc startSnapshot(buffer: openArray[int16], l: Natural = buffer.len) = # this is only called from cpu thread
  withLock(audioMutex):
    recordToSnapshot = true
    snapshotSize = l
    snapshotBuffer = cast[ptr UncheckedArray[int16]](addr buffer[0])
    snapshotIdx = 0
    acquire(snapshotMutex)

# this needs to be forward declared so the audio callback knows what to call
proc endSnapshot() = # this is only called from the audio thread
  recordToSnapshot = false
  snapshotSize = 0
  snapshotBuffer = nil
  snapshotIdx = 0
  release(snapshotMutex)

# where the magic happens: entry point to all mixing starts here.
proc audioInputCallback(buffer: pointer; frames: uint32) {.cdecl.} =
  const dt = 1/sampleRate.float
  let arr = cast[ptr UncheckedArray[int16]](buffer)
  withLock(audioMutex): # this may introduce latency, might be better to lock each note processing
    for i in 0..<frames:
      let bits = sampleToInt16(allSynthFinalSamples())
      arr[i] = bits 
      if recording:
        recordBuffer.add(bits)
      if recordToSnapshot:
        if snapshotIdx < snapshotSize:
          snapshotBuffer[snapshotIdx] = bits
          inc snapshotIdx
        else:
          endSnapshot()
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
  #s.oscillators.add(Oscillator(sampler: oscTriangle, envelope: EnvelopeADSR(attackTime: 0.02, attackVolume: 1.0, decayTime: 0.1, sustainVolume: 0.0, releaseTime: 0.0)))
  s.oscillators.add(Oscillator(sampler: oscSine, envelope: EnvelopeADSR(attackTime: 1.0, attackVolume: 1.0, decayTime: 0.3, sustainVolume: 0.9, releaseTime: 2.0)))
  s.oscillators.add(Oscillator(sampler: oscSquare, tonalOffset: 12.0, envelope: EnvelopeADSR(attackTime: 10.0, attackVolume: 1.0, decayTime: 0.0, sustainVolume: 1.0, releaseTime: 1.0)))
  s.volume = masterVolume
  initLock audioMutex
  initLock snapshotMutex
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
    echo &"saving {recordBuffer.len} frames..."
    outputWave.data = recordBuffer[0].addr
    outputWave.frameCount = uint32 recordBuffer.len()
    let micros = now().format("ffffff")
    if not exportWave(outputWave, &"{micros}.wav"):
      echo "ERROR: could not export wave"
    outputWave.data = nil
    outputWave.frameCount = 0
    recordBuffer.reset()

# TODO: abstract away the id to the user
proc noteOn*(s: ref Synth; tone: Semitone; velocity: float = 1.0): tuple[startId: int, endId: int] = 
  echo &"activating note with id: {s.activeNotes.len}, and tone of: {tone}"
  withLock(audioMutex):
    let curTime = cpuTime()
    let startId = s.activeNotes.len
    result = (startId: startId, endId: s.activeNotes.len + s.oscillators.len - 1)
    echo "got past lock after note on..."
    for osc in s.oscillators:
      s.activeNotes.add((note: Note(velocity: velocity, tone: tone, onTime: curTime, offTime: 0), oscillator: addr osc))
    echo &"sent note: {s.activeNotes[^1]}, ids: {result}"

proc noteOff*(s: ref Synth, ids: tuple[startId: int, endId: int]) =
  withLock(audioMutex):
    for i in countup(ids.startId, ids.endId):
      s.activeNotes[i].note.offTime = cpuTime()
  echo &"turned off noteids: {ids}"

proc handleInput*(s: ref Synth) =
  for i, key in keyMapping.pairs:
    if isKeyPressed(key):
      s.activeKeyIds[i] = (ids: s.noteOn(i.Semitone), held: true)
    if isKeyReleased(key):
      s.noteOff(s.activeKeyIds[i].ids)
  if isKeyPressed(startRecordingKey):
    startRecording()
  if isKeyPressed(stopRecordingKey):
    stopRecording()

# for interfacing with visuals or filters
# NOTE: blocks thread
proc requestSnapshot*(buffer: openArray[int16], l: Natural = buffer.len) = 
  assert(l < maxSnapshotSamples)
  startSnapshot(buffer, l)
  # block this thread until endSnapshot is called
  acquire(snapshotMutex) # this is probably dumb
  release(snapshotMutex)