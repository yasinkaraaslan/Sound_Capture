#module_parameters(VERBOSE := true);

// TODO(Yasin): Seperate thread.!!


Input_Device :: struct {
    name: string;
    internal_id: *void;
    internal_data: *void;
}

sound_capture_devices: [..]Input_Device;

SAMPLE_RATE :: 48000;
NUM_CHANNELS :: 2;
BIT_DEPTH :: 16;
BLOCK_ALIGN :: NUM_CHANNELS * BIT_DEPTH / 8;

#scope_module

capture_thread: Thread;
capture_mutex: Mutex;

#import "Thread";

#if OS == {
case .WINDOWS; #load "backend/wasapi.jai";
case .LINUX;   #load "backend/alsa.jai";
case .ANDROID; #load "backend/aaudio.jai";
}