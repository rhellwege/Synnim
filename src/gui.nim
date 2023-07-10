import raylib, raymath
import "synth.nim"

const
    snapshotSize: Natural = 256*256

var
    snapshotBuffer: array[snapshotSize, int16]

proc drawAnalyzerToRect*(r: Rectangle) =
    assert(r.width.toInt() < snapshotSize)
    requestSnapshot(snapshotBuffer, r.width.toInt()) # communicate with the synth
    for xCoord in countup(0, (r.width-1).toInt()):
        #let sampleX = xCoord * (snapshotSize.toFloat() / r.width).toInt()
        let sampleY = ((r.height/2)*(int16ToSample(snapshotBuffer[xCoord]))) + (r.height / 2)
        #echo int16ToSample(snapshotBuffer[xCoord])
        drawPixel(Vector2(x: xCoord.toFloat(), y: sampleY), Red)

proc drawEnvelopeToRect*(e: EnvelopeADSR, r: Rectangle) =
    discard

proc drawOscillatorToRect*(o: Oscillator, r: Rectangle) =
    discard

proc drawSynthToRect*(s: Synth, r: Rectangle) =
    discard