# signal processing procs like dft
import complex, math, bitops, unittest

proc dft*(samples: openArray[Complex], output: var openArray[Complex], N: Natural) =
  for freq in 0..<N:
      output[freq] = Complex(re: 0.0, im: 0.0)
      for i in 0..<N:
          let sample = samples[i]
          output[freq] += sample * exp(Complex(re: 0, im: -(TAU * freq.toFloat() * i.toFloat())/N.toFloat()))

proc dft*(samples: openArray[float], output: var openArray[Complex], N: Natural) =
  for freq in 0..<N:
      output[freq] = Complex(re: 0.0, im: 0.0)
      for i in 0..<N:
          let sample = samples[i]
          output[freq] += sample * exp(Complex(re: 0, im: (TAU * freq.toFloat() * i.toFloat())/N.toFloat()))
 
proc fftImpl(input: openArray[float], output: var openArray[Complex], N: Natural, stride: Natural) =
  assert(N > 0)
  if N == 1:
    output[0].re = input[0]
    output[0].im = input[0]
    return
  fftImpl(input, output, N div 2, stride * 2)
  fftImpl(input.toOpenArray(stride, input.len()-1), output.toOpenArray(N div 2, output.len()-1), N div 2, stride * 2)

  for k in countUp(0, N div 2 - 1):
    let v = output[k + N div 2] * exp(Complex(re: 0, im: -TAU*k.toFloat()/N.toFloat()))
    let e = output[k]
    output[k]           = e + v
    output[k + N div 2] = e - v

proc fft*(input: openArray[float], output: var openArray[Complex], N: Natural) =
  assert(countSetBits(N) == 1)
  fftImpl(input, output, N, 1)
 