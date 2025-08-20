// Sound capture module!
// Usage:
//
// Use capture_init() and capture_deinit() to initialize and deinitialize the module.
//
// Call start_recording() before reading sound buffers.
// You can poll sound buffers with get_next_sound_buffer().
// The buffer should be 16 bit depth, 2 channels, with 48000 sampling rate.
// (which you can see below in the constants)
// When you are done reading, call stop_recording().
//
// You want to call refresh_capture_devices() once in a while
// (when a user goes into the options tab in a game, for example).
//
// sound_capture_devices is an Input_Device array you can iterate.
// It refreshes when you call refresh_capture_devices().
// Input_Device struct contains a human-readable name and some internal data.
// You can set an input device as the current device with set_capture_device()
//
// get_default_capture_device() will give you the latest known default device.
// Its result depends when your latest call to refresh_capture_devices() was.
// Note that its result may not be consistent across different OSes,
// if you unplugged a device, for example.
// So make sure that you recently called refresh_capture_devices() before
// calling get_default_capture_device().


// TODO(Yasin): Specifying buffer size

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
#import "Basic";

#if OS == {
case .WINDOWS; #load "backend/wasapi.jai";
case .LINUX;   #load "backend/alsa.jai";
case .ANDROID; #load "backend/aaudio.jai";
}