#module_parameters(VERBOSE := true);

// TODO(Yasin): Seperate thread.!!


Input_Device :: struct {
    name: string;
    internal_id: *void;
    internal_data: *void;
}

#scope_module

SAMPLING_RATE :: 48000;
CHANNELS :: 2;
BIT_RATE :: 16;
BLOCK_SIZE :: CHANNELS * BIT_RATE / 8;


capture_thread: Thread;
capture_mutex: Mutex;

#import "Thread";

#if OS == {
case .WINDOWS; #load "backend/wasapi.jai";
case .LINUX;   #load "backend/alsa.jai";
case .ANDROID; #load "backend/aaudio.jai";
}