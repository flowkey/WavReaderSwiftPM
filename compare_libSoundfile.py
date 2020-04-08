import os
import soundfile
import matplotlib.pyplot as plt
from ctypes import CDLL, c_int, c_float, c_char_p, POINTER


# build and run:
# swift build -c release && python3 compare_libSoundfile.py


LIB_PATH = ".build/x86_64-apple-macosx/release/libWavReader.dylib"
WAV_FILE = "/Tests/Wavs/24bit-48000.wav"
BLOCK_SIZE = 1024


def main():
    wav_file_path = os.getcwd() + WAV_FILE

    # get first block of audio from WavReader CAPI
    wav_reader_lib = get_wav_reader_lib()
    ptr = c_char_p(wav_file_path.encode())
    wav_reader_lib.initialize(ptr, BLOCK_SIZE)
    block_from_wavreader = (c_float * BLOCK_SIZE)()
    err = wav_reader_lib.get_next_block(block_from_wavreader)
    print("error: ", err)

    # get first block of audio from soundfile
    blocks = soundfile.blocks(wav_file_path, BLOCK_SIZE)
    block_from_soundfile = next(blocks)

    # plot samples
    plt.plot(block_from_wavreader)
    plt.plot(block_from_soundfile)
    plt.show()

    # plot differences
    diff = [a-b for (a, b) in zip(block_from_soundfile, block_from_wavreader)]
    plt.plot(diff)
    plt.show()


def get_wav_reader_lib():
    lib = CDLL(LIB_PATH)

    lib.initialize.argtypes = [c_char_p, c_int]
    lib.initialize.restype = None
    lib.get_next_block.argtypes = [POINTER(c_float)]
    lib.get_next_block.restype = c_int

    return lib


if __name__ == "__main__":
    main()
