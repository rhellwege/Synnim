import std/[math, strformat, times, random, locks]
import os
import raylib, raymath, jsony

when compileoption("profiler"):
  import nimprof

when defined(windows): # do not include windows functions that collide with the raylib namespace
  {.localPassc: "-DNODRAWTEXT".} # TODO: Apply patch to raylib.h that adds #undef LoadImage on install

# TODO: refactor global variables to a context struct for readability
# TODO: add other effects like chorus, reverb, distortion, ...
# TODO: Envelope should be on the same level as filters so that an envelope can modify filters
# TODO: we need to differentiate between global envelopes and note envelopes.
# TODO: GUI
# TODO: MIDI live and playback
# TODO: figure out resizing
# TODO: antialiasing
# TODO: get good patches that sound like real instruments
# TODO: improve fft visualizer
# TODO: add glide, and max number of notes pressed at once (sends off event to each note before it in a quieue)
#       note envelopes operate on the note level (volume or tonalOffset of specific note)
#  Note :program mutes audio when release time is 0
#       global envelopes are triggered when ANY key is pressed and only trigger off when ALL keys are released
# private constants
type
  Hz* = float
  Semitone* = float

const
  sampleRate = 44100 # Hz
  maxSamplesPerUpdate = 4096
  tonalSystem = 12      # 12 semitone system
  tonalroot2 = pow(2.0, 1.0 / tonalSystem.float)
  baseFreq*: Hz = 110.0 # low A
  keyMapping: seq[KeyBoardKey] = @[Z, S, X, C, F, V, G, B, N, J, M, K, Comma, L, Period] # for input
  startRecordingKey: KeyBoardKey = One
  stopRecordingKey: KeyBoardKey = Two
  noteDeactivateThresh: float = 0.001
  maxSampleHeight = 32_000
  patchDir = currentSourcePath().parentDir().parentDir() / "assets/patches"
  recordingsDir = currentSourcePath().parentDir().parentDir() / "recordings"

type
  Note = object # runtime only
    tone: Semitone = 0
    tonalOffset: float = 0 # tonalOffset
    volume: float
    onTime: float = 0
    offTime: float = 0
    offValue: float = 0 # for envelope to keep track of value when released
    velocity: float = 0
    active: bool = true
  EnvelopeTarget* = enum
    Volume
    TonalOffset
    # global envelope only (cannot be evaluated per note
    HighPass 
    LowPass
  Envelope* = object # envelopes only act on the level of notes
    initialValue: float = 0
    attackTime*: float = 0
    decayTime*: float = 0
    releaseTime*: float = 0
    sustainValue*: float = 1
    attackValue*: float = 1
    targetType: EnvelopeTarget = Volume
  Sampler* = enum
    Sine
    Square
    Sawtooth
    Triangle
    Noise
    Wav # unsupported
  Oscillator* =  object
    sampler*: Sampler
    freqOffset*: Hz = 0.0
    tonalOffset*: Semitone = 0.0
    phase*: float = 0
    volume*: float = 1.0
    envelope*: Envelope
  LfoTarget* = enum
    Volume
    TonalOffset
    FreqOffset
    HighPass
    LowPass
  Lfo* = object
    freq: Hz
    sampler*: Sampler
    `low`: float
    `high`: float
    target: LfoTarget
    offset: float = 0.0
  AudioFilterType* = enum
    HighPass
    LowPass
  AudioFilter = object
    kind*: AudioFilterType
    alpha*: float = 1.0 # value between 0 and 1, determines the 'strength' of the filter
    firstSample: bool = true
    prevSample: float = 0.0
    prevFilteredSample: float = 0.0
  Patch = object # compiletime information
    oscillators*: seq[Oscillator] = @[]
    lfos*: seq[Lfo] = @[] # should this be contained inside oscillator?
    filters*: seq[AudioFilter] = @[]
    globalEnvelopes*: seq[Envelope] = @[]
    freqOffset*: Hz = 0
    tonalOffset*: Semitone = 0.0
    volume*: float = 0
  Synth* = object # runtime information
    patch*: Patch
    activeNotes*: seq[tuple[note: Note, oscillator: Natural]] = @[] # dont use pointer, use index
    activeKeyIds: array[keyMapping.len, tuple[ids: tuple[startId: int, endId: int], held: bool]]
    
# static variables
var
  masterVolume* = 0.5
  globalt*: float = 0
  stream: AudioStream
  synths: seq[ref Synth]
  recording: bool = false
  audioMutex*: Lock
  recordBuffer: seq[int16]
  outputWave: Wave = Wave(sampleSize: 16, sampleRate: sampleRate, channels: 1, data: nil)
  prevSample: float = 0.0
  prevFilteredSample: float = 0.0
  firstSample: bool = true
  highPassAlpha*: float = 0.1

converter toFreq*(s: Semitone): Hz =
  return Hz baseFreq * pow(tonalroot2, s)

func sampleToInt16*(sample: float): int16 =
  return int16(maxSampleHeight.toFloat()*sample)

func int16ToSample*(bits: int16): float =
  return bits.toFloat()/maxSampleHeight.toFloat()

proc applyEnvelope(n: var Note, e: Envelope) = # we need access to the filters
  let curTime = cpuTime()
  let sinceOn = curTime - n.onTime
  if n.onTime > n.offTime: # the user is holding the note
    if sinceOn <= e.attackTime:
      n.offValue = remap(sinceOn, 0.0, e.attackTime, 0.0, e.attackValue)
      n.volume = n.offValue
    elif sinceOn <= e.attackTime + e.decayTime:
      n.offValue = remap(sinceOn - e.attackTime, 0.0, e.decayTime, e.attackValue, e.sustainValue)
      n.volume = n.offValue
    else:
      n.offValue = e.sustainValue
      n.volume = e.sustainValue
  else:
    let sinceOff = curTime - n.offTime
    if sinceOff <= e.releaseTime and n.volume > noteDeactivateThresh:
      n.volume = remap(sinceOff, 0.0, e.releaseTime, n.offValue, 0.0)
    else:
      n.active = false
      n.volume = 0.0

proc oscSine(t: float, f: Hz): float {.inline.} =
  result = sin(2*PI*f*t)

proc oscTriangle(t: float, f: Hz): float {.inline.} =
  result = arcsin(sin(2*PI*f*t))

proc oscSquare(t: float, f: Hz): float {.inline.} =
  result = sin(2*PI*f*t)
  result = if result < 0.0: -1.0 else: 1.0

proc oscSawtooth(t: float, f: Hz): float {.inline.} =
  result = (2*t*f mod 2.0) - 1.0

proc oscNoise(t: float, f: Hz): float {.inline.} =
  result = rand(2.0) - 1.0

proc evalSampler(kind: Sampler, t: float, f: float): float {.inline.} =
  case kind:
  of Sine:
    return oscSine(t, f)
  of Triangle:
    return oscTriangle(t, f)
  of Square:
    return oscSquare(t, f)
  of Sawtooth:
    return oscSawTooth(t, f)
  of Noise:
    return oscNoise(t, f)
  else:
    raise newException(OSError, "Sampler not supported.")

proc filterHighPass(a: var AudioFilter, sample: float): float {.inline.} =
  if a.firstSample: ## filtering
    a.prevSample = sample
    a.prevFilteredSample = sample
    a.firstSample = false
    return sample # first iteration, return the sample as is
  else: # still filtering
    let temp = sample
    result = a.alpha * (a.prevFilteredSample + sample - a.prevSample)
    a.prevFilteredSample = result
    a.prevSample = temp
    
proc filterLowPass(a: var AudioFilter, sample: float): float {.inline.} =
  if a.firstSample: ## filtering
    a.prevSample = sample
    a.prevFilteredSample = sample
    a.firstSample = false
    return sample # first iteration, return the sample as is
  else: # still filtering
    let temp = sample
    result = a.prevFilteredSample + a.alpha * (sample - a.prevFilteredSample)
    a.prevFilteredSample = result
    a.prevSample = temp

proc evalFilter(a: var AudioFilter; sample: float): float {.inline.} =
  case a.kind:
  of LowPass:
    return filterLowPass(a, sample)
  of HighPass:
    return filterHighPass(a, sample)

proc applyLfo*(syn: ref Synth; l: var Lfo; t: float) {.inline.} = # ensure that modifier is valid memory
  let sample = l.sampler.evalSampler(l.freq, t)
  let nextValue = l.offset + remap(sample, -1.0, 1.0, l.`low`, l.`high`)
  case l.target:
  of Volume:
    syn.patch.volume = nextValue
  of TonalOffset:
    syn.patch.tonalOffset = nextValue
  of FreqOffset:
    syn.patch.freqOffset = nextValue
  else:
    raise newException(OSError, "Lfo target not supported.")

proc finalSample(t: float): float =
  for syn in synths:
    for note, oscIndex in syn.activeNotes.items():
      if note.active:
        let finalFrequency = (note.tone + syn.patch.oscillators[oscIndex].tonalOffset + syn.patch.tonalOffset).toFreq() + syn.patch.oscillators[oscIndex].freqOffset + syn.patch.freqOffset
        result += note.volume * syn.patch.oscillators[oscIndex].sampler.evalSampler(t, finalFrequency)
    result *= syn.patch.volume # apply synth volume
    # apply filtering on the result, rendering loop may mess with the filtering, which will introduce artifacts
    for filter in syn.patch.filters.mitems():
      result = filter.evalFilter(result)
  result *= masterVolume # apply master volume

proc runSampler*(frames: Natural, dt: float, callback: proc (sample: float, sampleIdx: float)) =
  # t is implied to be 0
  # save the state of all synths so what we do doesnt affect anything
  withLock(audioMutex):
    var savedFilters: seq[AudioFilter] = @[]
    for synth in synths:
      for filter in synth.patch.filters.mitems():
        savedFilters.add(filter)
        filter.firstSample = true
        filter.prevFilteredSample = 0.0
    for i in 0..<frames:
      callback(finalSample(i.toFloat()*dt), i.toFloat())
    var index = 0
    for synth in synths:
      for filter in synth.patch.filters.mitems():
        filter = savedFilters[index]
        inc index

# where the magic happens: entry point to all mixing starts here.
proc audioInputCallback(buffer: pointer; frames: uint32) {.cdecl.} =
  const dt = 1/sampleRate.float
  let arr = cast[ptr UncheckedArray[int16]](buffer)
  withLock(audioMutex):
    for syn in synths:
      for lfo in syn.patch.lfos.mitems():
        syn.applyLfo(lfo, globalt)
      for note, oscIndex in syn.activeNotes.mitems():
        note.applyEnvelope(syn.patch.oscillators[oscIndex].envelope)
      # delete in active notes
      while syn.activeNotes.len() > 0 and not syn.activeNotes[^1].note.active:
        discard syn.activeNotes.pop()
    for i in 0..<frames:
      var curSample = finalSample(globalt)
      arr[i] = sampleToInt16(curSample) # set the sample in the buffer
      if recording:
        recordBuffer.add(sampleToInt16(curSample))
      globalt += dt
    #lowPass(buffer, frames, 0.01)

proc savePatch*(p: Patch, name: string) =
  writeFile(patchDir / name & ".json", p.toJson())

proc loadPatch*(name: string): Patch =
  let contents = readFile(patchDir / name & ".json")
  return contents.fromJson(Patch)

# public interface
proc init*(s: ref Synth) =
  if not isAudioDeviceReady():
    initAudioDevice()
    setAudioStreamBufferSizeDefault(maxSamplesPerUpdate)
  s.patch = loadPatch("basic-synth")
  # s.patch.oscillators.add(Oscillator(sampler: Triangle, envelope: Envelope(attackTime: 0.2, attackValue: 1.0, decayTime: 01.0, sustainValue: 0.0, releaseTime: 0.1)))
  # s.patch.oscillators.add(Oscillator(sampler: Sine, tonalOffset: 0, envelope: Envelope(attackTime: 0.3, attackValue: 0.9, decayTime: 0.3, sustainValue: 0.9, releaseTime: 0.2)))
  # s.patch.oscillators.add(Oscillator(volume: 0.5, sampler: Sawtooth, tonalOffset: 0.0, envelope: Envelope(attackTime: 0.2, attackValue: 1.0, decayTime: 0.0, sustainValue: 1.0, releaseTime: 0.1)))
  # s.patch.filters.add(AudioFilter(kind: LowPass))
  # s.patch.filters.add(AudioFilter(kind: HighPass))
  # s.patch.volume = masterVolume
  #s.patch.savePatch("basic-synth")
  # s.patch.lfos.add(Lfo(sampler: Triangle, `low`: 0.0, `high`: 12.0, freq: 0.1, target: TonalOffset))
  # s.patch.savePatch("basic-synth")
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
    echo &"saving {recordBuffer.len} frames..."
    outputWave.data = recordBuffer[0].addr
    outputWave.frameCount = uint32 recordBuffer.len()
    let micros = now().format("ffffff")
    if not exportWave(outputWave, recordingsDir / &"{micros}.wav"):
      echo "ERROR: could not export wave"
    outputWave.data = nil
    outputWave.frameCount = 0
    recordBuffer.reset()

proc noteOn(s: ref Synth; tone: Semitone; velocity: float = 1.0): tuple[startId: int, endId: int] = 
  withLock(audioMutex):
    let curTime = cpuTime()
    let startId = s.activeNotes.len
    result = (startId: startId, endId: s.activeNotes.len + s.patch.oscillators.len - 1)
    for i, osc in s.patch.oscillators.pairs():
      s.activeNotes.add((note: Note(velocity: velocity, tone: tone, onTime: curTime, offTime: 0), oscillator: Natural i))

proc noteOff(s: ref Synth, ids: tuple[startId: int, endId: int]) =
  withLock(audioMutex):
    for i in countup(ids.startId, ids.endId):
      s.activeNotes[i].note.offTime = cpuTime()

proc handleInput*(s: ref Synth) =
  for i, key in keyMapping.pairs():
    if isKeyPressed(key):
      s.activeKeyIds[i] = (ids: s.noteOn(i.Semitone), held: true)
    if isKeyReleased(key):
      s.noteOff(s.activeKeyIds[i].ids)
  if isKeyPressed(startRecordingKey):
    startRecording()
  if isKeyPressed(stopRecordingKey):
    stopRecording()