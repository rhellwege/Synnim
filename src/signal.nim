# signal processing procs like dft
import complex, math



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
          output[freq] += sample * exp(Complex(re: 0, im: -(TAU * freq.toFloat() * i.toFloat())/N.toFloat()))
