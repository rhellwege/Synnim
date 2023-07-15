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

# TODO: make low pass and high pass filters a part of the synth

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

type
  Note = object
    tone: Semitone = 0
    volume: float
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
    #modifier*: ptr float = nil
  OscillatorSampler* = proc(t: float, f: Hz): float
  Oscillator* =  object
    sampler*: OscillatorSampler
    freqOffset*: Hz = 0.0
    tonalOffset*: Semitone = 0.0
    timeOffset*: float = 0
    volume*: float = 1.0
    envelope*: EnvelopeADSR
  Lfo* = object
    freq: Hz
    sampler*: OscillatorSampler
    `low`: float
    `high`: float
    modifier: ptr float # maybe we should make this an array, also should we be using pointers?
    initialValue: float = 0.0
  AudioFilterProc = proc(a: var AudioFilter, sample: float): float # take a sample, do math, save the previus results inside the filter
  AudioFilter* = object
    filterProc*: AudioFilterProc
    alpha*: float = 1.0 # value between 0 and 1, determines the 'strength' of the filter
    firstSample: bool = true
    prevSample: float = 0.0
    prevFilteredSample: float = 0.0
  Synth* = object
    freqOffset*: Hz = 0
    tonalOffset*: Semitone = 0.0
    volume*: float = 0
    oscillators*: seq[Oscillator] = @[]
    #noteIds: seq[seq[Natural]] = @[] # dont use pointer, use index
    activeNotes*: seq[tuple[note: Note, oscillator: Natural]] = @[] # dont use pointer, use index
    activeKeyIds: array[keyMapping.len, tuple[ids: tuple[startId: int, endId: int], held: bool]]
    lfos*: seq[Lfo] = @[]
    filters*: seq[AudioFilter] = @[]
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
  # filtering
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

proc applyEnvelope(n: var Note, e: EnvelopeADSR) = # we need to change the structure of the oscilators and the notes
  let curTime = cpuTime()
  let sinceOn = curTime - n.onTime
  if n.onTime > n.offTime: # the user is holding the note
    if sinceOn <= e.attackTime:
      n.offVolume = remap(sinceOn, 0.0, e.attackTime, 0.0, e.attackVolume)
      n.volume = n.offVolume
    elif sinceOn <= e.attackTime + e.decayTime:
      n.offVolume = remap(sinceOn - e.attackTime, 0.0, e.decayTime, e.attackVolume, e.sustainVolume)
      n.volume = n.offVolume
    else:
      n.offVolume = e.sustainVolume
      n.volume = e.sustainVolume
  else:
    let sinceOff = curTime - n.offTime
    if sinceOff <= e.releaseTime and n.volume > noteDeactivateThresh:
      n.volume = remap(sinceOff, 0.0, e.releaseTime, n.offVolume, 0.0)
    else:
      n.active = false
      n.volume = 0.0

proc oscSine(t: float, f: Hz): float =
  result = sin(2*PI*f*t)

proc oscTriangle(t: float, f: Hz): float =
  result = arcsin(sin(2*PI*f*t))

proc oscSquare(t: float, f: Hz): float =
  result = sin(2*PI*f*t)
  result = if result < 0.0: -1.0 else: 1.0

proc oscSawtooth(t: float, f: Hz): float =
  result = (2*t*f mod 2.0) - 1.0

proc oscNoise(t: float, f: Hz): float =
  result = rand(2.0) - 1.0

proc filterHighPass(a: var AudioFilter, sample: float): float =
  if a.firstSample: ## filtering
    a.prevSample = sample
    a.firstSample = false
    return sample # first iteration, return the sample as is
  else: # still filtering
    let temp = sample
    result = a.alpha * (a.prevFilteredSample + sample - a.prevSample)
    a.prevFilteredSample = result
    a.prevSample = temp

proc filterLowPass(a: var AudioFilter, sample: float): float =
  if a.firstSample: ## filtering
    a.prevSample = sample
    a.firstSample = false
    return sample # first iteration, return the sample as is
  else: # still filtering
    let temp = sample
    result = a.prevFilteredSample + a.alpha * (sample - a.prevFilteredSample)
    a.prevFilteredSample = result
    a.prevSample = temp

proc applyLfo*(l: var Lfo, t: float) = # ensure that modifier is valid memory
  let sample = l.sampler(l.freq, t)
  l.modifier[] = l.initialValue + remap(sample, -1.0, 1.0, l.`low`, l.`high`)

proc finalSample(t: float): float = # TODO: make this proc private, and add a user api, which does not modify any information, and allows the user to pass a proc lambda
  for syn in synths:
    for note, oscIndex in syn.activeNotes.items():
      if note.active:
        let finalFrequency = (note.tone + syn.oscillators[oscIndex].tonalOffset + syn.tonalOffset).toFreq() + syn.oscillators[oscIndex].freqOffset + syn.freqOffset
        result += note.volume * syn.oscillators[oscIndex].sampler(t, finalFrequency)
    result *= syn.volume # apply synth volume
    # apply filtering on the result, rendering loop may mess with the filtering, which will introduce artifacts
    for filter in syn.filters.mitems():
      result = filter.filterProc(filter, result)
  result *= masterVolume # apply master volume

proc runSampler*(frames: Natural, dt: float, callback: proc (sample: float, sampleIdx: float)) =
  # t is implied to be 0
  # save the state of all synths so what we do doesnt affect anything
  withLock(audioMutex):
    var savedFilters: seq[AudioFilter] = @[]
    for synth in synths:
      for filter in synth.filters.mitems():
        savedFilters.add(filter)
        filter.firstSample = true
        filter.prevFilteredSample = 0.0
    for i in 0..<frames:
      callback(finalSample(i.toFloat()*dt), i.toFloat())
    var index = 0
    for synth in synths:
      for filter in synth.filters.mitems():
        filter = savedFilters[index]
        inc index

# where the magic happens: entry point to all mixing starts here.
proc audioInputCallback(buffer: pointer; frames: uint32) {.cdecl.} =
  const dt = 1/sampleRate.float
  let arr = cast[ptr UncheckedArray[int16]](buffer)
  withLock(audioMutex): # this may introduce latency, might be better to lock each note processing
    for syn in synths:
      for lfo in syn.lfos.mitems():
        lfo.applyLfo(globalt)
      for note, oscIndex in syn.activeNotes.mitems():
        note.applyEnvelope(syn.oscillators[oscIndex].envelope)
      # delete in active notes
      while syn.activeNotes.len() > 0 and not syn.activeNotes[^1].note.active:
        discard syn.activeNotes.pop()
    for i in 0..<frames:
      var curSample = finalSample(globalt)
      # for syn in synths: we sample in the finalSample proc
      #   for filter in syn.filters.mitems():
      #     curSample = filter.filterProc(filter, curSample)
      arr[i] = sampleToInt16(curSample) # set the sample in the buffer
      if recording:
        recordBuffer.add(sampleToInt16(curSample))
      globalt += dt
    #lowPass(buffer, frames, 0.01)

# public interface
proc init*(s: ref Synth) =
  if not isAudioDeviceReady():
    initAudioDevice()
    setAudioStreamBufferSizeDefault(maxSamplesPerUpdate)
  s.oscillators.add(Oscillator(sampler: oscTriangle, envelope: EnvelopeADSR(attackTime: 0.2, attackVolume: 1.0, decayTime: 01.0, sustainVolume: 0.0, releaseTime: 0.1)))
  s.oscillators.add(Oscillator(sampler: oscSine, tonalOffset: 0, envelope: EnvelopeADSR(attackTime: 0.3, attackVolume: 0.9, decayTime: 0.3, sustainVolume: 0.9, releaseTime: 0.2)))
  s.oscillators.add(Oscillator(volume: 0.5, sampler: oscSawtooth, tonalOffset: 0.0, envelope: EnvelopeADSR(attackTime: 0.2, attackVolume: 1.0, decayTime: 0.0, sustainVolume: 1.0, releaseTime: 0.1)))
  s.filters.add(AudioFilter(filterProc: filterLowPass))
  s.filters.add(AudioFilter(filterProc: filterHighPass))
  # s.lfos.add(Lfo(sampler: oscSquare, `low`: 0.0, `high`: 3.0, freq: 1.0, modifier: addr s.tonalOffset))
  # s.lfos.add(Lfo(sampler: oscSquare, `low`: 0.0, `high`: 7.0, freq: 2.0))
  # s.lfos.add(Lfo(sampler: oscSquare, `low`: 0.0, `high`: 12.0, freq: 4.0))
  # s.lfos[1].modifier = addr s.lfos[0].initialValue
  # s.lfos[2].modifier = addr s.lfos[1].initialValue
  # s.lfos.add(Lfo(sampler: oscSine, freq: 16.0, `low`: 0.1, `high`: 1.0, modifier: addr s.filters[0].alpha))
  s.volume = masterVolume
  # s.lfos.add(Lfo(sampler: oscTriangle, `low`: 0.0, `high`: 12.0, freq: 0.1, modifier: addr s.tonalOffset))
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
    if not exportWave(outputWave, &"{micros}.wav"):
      echo "ERROR: could not export wave"
    outputWave.data = nil
    outputWave.frameCount = 0
    recordBuffer.reset()

# TODO: abstract away the id to the user
proc noteOn*(s: ref Synth; tone: Semitone; velocity: float = 1.0): tuple[startId: int, endId: int] = 
  withLock(audioMutex):
    let curTime = cpuTime()
    let startId = s.activeNotes.len
    result = (startId: startId, endId: s.activeNotes.len + s.oscillators.len - 1)
    for i, osc in s.oscillators.pairs():
      s.activeNotes.add((note: Note(velocity: velocity, tone: tone, onTime: curTime, offTime: 0), oscillator: Natural i))

proc noteOff*(s: ref Synth, ids: tuple[startId: int, endId: int]) =
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