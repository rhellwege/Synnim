# signal processing procs like dft
import complex

proc dft(samples: openArray[Complex], output: openArray[Complex], N: Natural) =
    discard