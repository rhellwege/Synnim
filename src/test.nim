import unittest, "signal.nim", math, complex
suite "slices":
  echo "arrays suite"
  setup:
    echo "Testing..."
  
  test "simple":
    var arr = [1,2,3,4,5]
    #var arrSlice35: seq[int] = 
    echo arr.toOpenArray(2, arr.len()-1).repr
    check(arr.toOpenArray(2, arr.len()-1)[0] == 3)
    arr.toOpenArray(2, arr.len()-1)[0] = 9
    check(arr[2] == 9)

suite "fourier":
  echo "fourier suite"
  const freq = 1
  const samples = [sin(0*TAU*freq), sin(1*TAU*freq), sin(0*TAU*freq), sin(1*TAU*freq)]
  var fftOutput: array[samples.len(), Complex[float]]
  var dftOutput: array[samples.len(), Complex[float]]
  setup:
    echo "vvvvvvv"
  test "fft/dft":
    fft(samples, fftOutput, samples.len())
    dft(samples, dftOutput, samples.len())
    for i, f in fftOutput.pairs():
      check(f == dftOutput[i])

    #test "fft":