capture_init :: () {
    refresh_capture_devices();
    set_capture_device(get_default_capture_device());
}

// This isn't actually required, as opposed to WASAPI.
start_recording :: () {
    hr := snd_pcm_start(current_device.internal_data);
    check_hr("Start PCM");
}

stop_recording :: () {
    hr := snd_pcm_drop(current_device.internal_data);
    check_hr("Drop PCM");
}

capture_deinit :: () {
    for * sound_capture_devices {
        free_device(it);
    }
    array_reset(*sound_capture_devices);
    current_device, default_device = null;
}

refresh_capture_devices :: () {
    for * sound_capture_devices {
        free_device(it);
    }
    array_reset(*sound_capture_devices);

    hints: **void;
    hr := snd_device_name_hint(-1, "pcm", *hints);
    defer snd_device_name_free_hint(hints);

    if !check_hr("Device name hint") return;

    n := hints;
    while n.* != null {
        dev_name := snd_device_name_get_hint(n.*, "NAME");

        if to_string(dev_name) == "null" {
            c_free(dev_name);
            n += 1;
            continue;
        }

        handle: *snd_pcm_t;
        hr = snd_pcm_open(*handle, dev_name, SND_PCM_STREAM_CAPTURE, SND_PCM_NONBLOCK);

        if hr < 0 {
            c_free(dev_name);
            n += 1;
            continue;
        }

        snd_pcm_close(handle);

        device := array_add(*sound_capture_devices);
        device.name = to_string(snd_device_name_get_hint(n.*, "DESC")); // Human readable name
        device.internal_id = dev_name;

        // device.internal_data = handle;

        if to_string(dev_name) == "default" {
            default_device = device;
        }
        n += 1;
    }

}

get_default_capture_device  :: () -> *Input_Device {
    return default_device;
}

set_capture_device :: (device: *Input_Device) {
    check :: (name: string) #expand {
        hr := `hr;
        if !check_hr(name) {
            log("Couldn't set capture device to '%'", `device.name);
            // snd_pcm_close(`pcm_device);
            `return;
        }
    }

    hr := snd_pcm_open(cast(**snd_pcm_t)*device.internal_data, device.internal_id, SND_PCM_STREAM_CAPTURE, SND_PCM_NONBLOCK);
    if !check_hr("Open sound device") {
        log("Couldn't set capture device to '%'", device.name);
        return;
    }
    pcm_device := cast(*snd_pcm_t)device.internal_data;

    hw_params: *snd_pcm_hw_params_t;
    snd_pcm_hw_params_malloc(*hw_params);
    defer snd_pcm_hw_params_free(hw_params);

    snd_pcm_hw_params_any(pcm_device, hw_params);

    hr = snd_pcm_hw_params_set_channels(pcm_device, hw_params, NUM_CHANNELS);
    check("Set PCM channels");

    hr = snd_pcm_hw_params_set_format(pcm_device, hw_params, SND_PCM_FORMAT_S16_MY_ENDIAN);
    check("Set PCM format");

    hr = snd_pcm_hw_params_set_access(pcm_device, hw_params, SND_PCM_ACCESS_RW_INTERLEAVED);
    check("Set PCM access");

    actual_rate: u32 = SAMPLE_RATE;
    hr = snd_pcm_hw_params_set_rate_near(pcm_device, hw_params, *actual_rate, null);
    check("Set PCM sample rate");

    hr = snd_pcm_hw_params_set_period_size(pcm_device, hw_params, 256, 0);
    check("Set PCM period size");

    hr = snd_pcm_hw_params(pcm_device, hw_params);
    check("Set PCM hardware parameters");

    hr = snd_pcm_prepare(pcm_device);
    check("Prepare PCM");

    if current_device && current_device.internal_data {
        snd_pcm_close(current_device.internal_data);
        current_device.internal_data = null;
    }

    current_device = device;
}

free_device :: (using device: *Input_Device) {
    if name        c_free(name.data);
    if internal_id c_free(internal_id);

    if internal_data {
        snd_pcm_close(internal_data);
    }
}

#scope_file
alsa :: #library,system "libasound";


crt :: #system_library "libc";
c_free :: (memory: *void) #foreign crt "free";

// @TODO this should be changed to file parameters when that becomes implemented
LITTLE_ENDIAN :: 0;
BIG_ENDIAN :: 1;
CPU_BYTE_ORDER :: LITTLE_ENDIAN;

// opaque structs
snd_pcm_t :: struct { }
snd_pcm_info_t :: struct { }
snd_pcm_hw_params_t :: struct { }
snd_pcm_sw_params_t :: struct { }

SND_PCM_STREAM_PLAYBACK :: 0;
SND_PCM_STREAM_CAPTURE  :: 0;


snd_pcm_stream_t :: u32;
snd_pcm_access_t :: u32;
snd_pcm_format_t :: u32;

SND_PCM_NONBLOCK :: 0x0001;
SND_PCM_ASYNC    :: 0x0002;

/*
SND_PCM_ACCESS_MMAP_INTERLEAVED    :: 0;
SND_PCM_ACCESS_MMAP_NONINTERLEAVED :: 1;
SND_PCM_ACCESS_MMAP_COMPLEX        :: 2;
SND_PCM_ACCESS_RW_NONINTERLEAVED   :: 4;
*/

SND_PCM_ACCESS_RW_INTERLEAVED      :: 3;

SND_PCM_FORMAT_S16_LE  :: 2;
SND_PCM_FORMAT_S16_BE  :: 3;

#if CPU_BYTE_ORDER == LITTLE_ENDIAN {
    SND_PCM_FORMAT_S16_MY_ENDIAN :: SND_PCM_FORMAT_S16_LE;
} else {
    SND_PCM_FORMAT_S16_MY_ENDIAN :: SND_PCM_FORMAT_S16_BE;
}

/*
SND_PCM_FORMAT_UNKNOWN ::-1;
SND_PCM_FORMAT_S8      :: 0;
SND_PCM_FORMAT_U8      :: 1;
SND_PCM_FORMAT_U16_LE  :: 4;
SND_PCM_FORMAT_U16_BE  :: 5;
SND_PCM_FORMAT_S24_LE  :: 6;
SND_PCM_FORMAT_S24_BE  :: 7;
SND_PCM_FORMAT_U24_LE  :: 8;
SND_PCM_FORMAT_U24_BE  :: 9;
SND_PCM_FORMAT_S32_LE  :: 10;
SND_PCM_FORMAT_S32_BE  :: 11;
SND_PCM_FORMAT_U32_LE  :: 12;
SND_PCM_FORMAT_U32_BE  :: 13;
SND_PCM_FORMAT_FLOAT_LE :: 14;
SND_PCM_FORMAT_FLOAT_BE :: 15;
SND_PCM_FORMAT_FLOAT64_LE :: 16;
SND_PCM_FORMAT_FLOAT64_BE :: 17;
SND_PCM_FORMAT_IEC958_SUBFRAME_LE :: 18;
SND_PCM_FORMAT_IEC958_SUBFRAME_BE :: 19;
SND_PCM_FORMAT_MU_LAW :: 20;
SND_PCM_FORMAT_A_LAW :: 21;
SND_PCM_FORMAT_IMA_ADPCM :: 22;
SND_PCM_FORMAT_MPEG :: 23;
SND_PCM_FORMAT_GSM :: 24;
SND_PCM_FORMAT_SPECIAL :: 31;
SND_PCM_FORMAT_S24_3LE :: 32;
SND_PCM_FORMAT_S24_3BE :: 33;
SND_PCM_FORMAT_U24_3LE :: 34;
SND_PCM_FORMAT_U24_3BE :: 35;
SND_PCM_FORMAT_S20_3LE :: 36;
SND_PCM_FORMAT_S20_3BE :: 37;
SND_PCM_FORMAT_U20_3LE :: 38;
SND_PCM_FORMAT_U20_3BE :: 39;
SND_PCM_FORMAT_S18_3LE :: 40;
SND_PCM_FORMAT_S18_3BE :: 41;
SND_PCM_FORMAT_U18_3LE :: 42;
SND_PCM_FORMAT_U18_3BE :: 43;
SND_PCM_FORMAT_G723_24 :: 44;
SND_PCM_FORMAT_G723_24_1B :: 45;
SND_PCM_FORMAT_G723_40    :: 46;
SND_PCM_FORMAT_G723_40_1B :: 47;
SND_PCM_FORMAT_DSD_U8     :: 48;
SND_PCM_FORMAT_DSD_U16_LE :: 49;
SND_PCM_FORMAT_DSD_U32_LE :: 50;
SND_PCM_FORMAT_DSD_U16_BE :: 51;
SND_PCM_FORMAT_DSD_U32_BE :: 52;
*/

snd_pcm_uframes_t :: u64;
snd_pcm_sframes_t :: s64;

snd_pcm_open :: (pcm: **snd_pcm_t, name: *u8, stream: snd_pcm_stream_t, mode: s32) -> s32 #foreign alsa;
snd_pcm_close :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;
snd_pcm_delay :: (pcm: *snd_pcm_t, delayp: *snd_pcm_sframes_t) -> s32 #foreign alsa;
snd_pcm_prepare :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;
snd_pcm_writei :: (pcm: *snd_pcm_t, buf: *void, size: snd_pcm_uframes_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_avail :: (pcm: *snd_pcm_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_avail_update :: (pcm: *snd_pcm_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_start :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;
snd_pcm_recover :: (pcm: *snd_pcm_t, err: s32, silent: s32) -> s32 #foreign alsa;
snd_pcm_drop :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;

snd_pcm_state_t :: enum u32 {
    SND_PCM_STATE_OPEN :: 0;
    SND_PCM_STATE_SETUP;
    SND_PCM_STATE_PREPARED;
    SND_PCM_STATE_RUNNING;
    SND_PCM_STATE_XRUN;
    SND_PCM_STATE_DRAINING;
    SND_PCM_STATE_PAUSED;
    SND_PCM_STATE_SUSPENDED;
    SND_PCM_STATE_DISCONNECTED;
}
snd_pcm_state :: (pcm: *snd_pcm_t) -> snd_pcm_state_t #foreign alsa;

/*
snd_pcm_nonblock :: (pcm: *snd_pcm_t, nonblock: s32) -> s32 #foreign alsa;
snd_pcm_reset :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;
snd_pcm_drain :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;
snd_pcm_wait :: (pcm: *snd_pcm_t, timeout: s32) -> s32 #foreign alsa;
*/


snd_pcm_set_params :: (pcm: *snd_pcm_t, format: snd_pcm_format_t, access: snd_pcm_access_t, channels: u32, rate: u32, soft_resample: s32, latency: u32) -> s32 #foreign alsa;

snd_pcm_hw_params :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t) -> s32 #foreign alsa;
snd_pcm_hw_params_any :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t) -> s32 #foreign alsa;
snd_pcm_hw_params_get_channels_max :: (params: *snd_pcm_hw_params_t, val: *u32) -> s32 #foreign alsa;
snd_pcm_hw_params_set_format :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: snd_pcm_format_t) -> s32 #foreign alsa;
snd_pcm_hw_params_set_access :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, access: snd_pcm_access_t) -> s32 #foreign alsa;

/*
snd_pcm_hw_params_set_channels_minmax :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, min: *u32, max: *u32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_channels_min :: (params: *snd_pcm_hw_params_t, val: *u32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_buffer_size_min :: (params: *snd_pcm_hw_params_t, val: *snd_pcm_uframes_t) -> s32 #foreign alsa;
snd_pcm_hw_params_get_buffer_time :: (params: *snd_pcm_hw_params_t, val: *u32, dir: *s32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_period_size_min :: (params: *snd_pcm_hw_params_t, frames: *snd_pcm_uframes_t, dir: *s32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_period_time :: (params: *snd_pcm_hw_params_t, val: *u32, dir: *s32) -> s32 #foreign alsa;
snd_pcm_hw_params_test_channels :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: u32) -> s32 #foreign alsa;
snd_pcm_hw_params_set_periods :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: u32, dir: s32) -> s32 #foreign alsa;
snd_pcm_hw_params_set_buffer_size :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: snd_pcm_uframes_t) -> s32 #foreign alsa;
*/

snd_pcm_hw_params_set_period_size :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: snd_pcm_uframes_t, dir: s32) -> s32 #foreign alsa;
snd_pcm_hw_params_set_rate_near :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: *u32, dir: *s32) -> s32 #foreign alsa;
snd_pcm_hw_params_set_channels :: (pcm: *snd_pcm_t, params: *snd_pcm_hw_params_t, val: u32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_rate :: (params: *snd_pcm_hw_params_t, val: *u32, dir: *s32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_channels :: (params: *snd_pcm_hw_params_t, val: *u32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_buffer_size :: (params: *snd_pcm_hw_params_t, val: *snd_pcm_uframes_t) -> s32 #foreign alsa;
snd_pcm_hw_params_get_periods :: (params: *snd_pcm_hw_params_t, val: *u32, dir: *s32) -> s32 #foreign alsa;
snd_pcm_hw_params_get_period_size :: (params: *snd_pcm_hw_params_t, frames: *snd_pcm_uframes_t, dir: *s32) -> s32 #foreign alsa;

snd_pcm_hw_params_malloc :: (ptr: **snd_pcm_hw_params_t) -> s32 #foreign alsa;
snd_pcm_hw_params_free :: (obj: *snd_pcm_hw_params_t) -> void #foreign alsa;

snd_pcm_sw_params :: (pcm: *snd_pcm_t, params: *snd_pcm_sw_params_t) -> s32 #foreign alsa;
snd_pcm_sw_params_malloc :: (ptr: **snd_pcm_sw_params_t) -> s32 #foreign alsa;
snd_pcm_sw_params_free :: (obj: *snd_pcm_sw_params_t) -> void #foreign alsa;


snd_pcm_sw_params_current :: (pcm: *snd_pcm_t, params: *snd_pcm_sw_params_t) -> s32 #foreign alsa;
snd_pcm_sw_params_get_start_threshold :: (params: *snd_pcm_sw_params_t, val: *snd_pcm_uframes_t) -> s32 #foreign alsa;
snd_pcm_sw_params_set_start_threshold :: (pcm: *snd_pcm_t, params: *snd_pcm_sw_params_t, val: snd_pcm_uframes_t) -> s32 #foreign alsa;
snd_pcm_sw_params_set_avail_min :: (pcm: *snd_pcm_t, params: *snd_pcm_sw_params_t, val: snd_pcm_uframes_t) -> s32 #foreign alsa;

/*
snd_pcm_poll_descriptors_revents :: (pcm: *snd_pcm_t, pfds: *pollfd, nfds: u32, revents: *u16) -> s32 #foreign alsa;
snd_pcm_poll_descriptors_count :: (pcm: *snd_pcm_t) -> s32 #foreign alsa;
snd_pcm_poll_descriptors :: (pcm: *snd_pcm_t, pfds: *pollfd, space: u32) -> s32 #foreign alsa;
*/


sound_error_name :: (errnum: s32) -> string {
    snd_strerror :: (errnum: s32) -> *u8 #foreign alsa;
    return to_string(snd_strerror(errnum));
}

check_for_alsa_error :: (name: string, errnum: s32) {
    if !errnum return;
    log_error("Sound_Player ALSA backend error: functionality %: result code %, %. Current state is %", name, errnum, sound_error_name(errnum), ifx pcm_device then snd_pcm_state(pcm_device) else cast(snd_pcm_state_t) U32_MAX);
}

// direct (mmap) API

snd_pcm_channel_area_t :: struct {
    addr: *void; // starting address of channel sample buffer
    first: u32; // bits
    step: u32;  // bits
}

snd_pcm_mmap_begin :: (pcm: *snd_pcm_t, areas: **snd_pcm_channel_area_t, offset: *snd_pcm_uframes_t, frames: *snd_pcm_uframes_t) -> s32 #foreign alsa;
snd_pcm_mmap_commit :: (pcm: *snd_pcm_t, offset: snd_pcm_uframes_t, frames: snd_pcm_uframes_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_mmap_writei :: (pcm: *snd_pcm_t, buffer: *void, size: snd_pcm_uframes_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_mmap_readi :: (pcm: *snd_pcm_t, buffer: *void, size: snd_pcm_uframes_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_mmap_writen :: (pcm: *snd_pcm_t, buffer: **void, size: snd_pcm_uframes_t) -> snd_pcm_sframes_t #foreign alsa;
snd_pcm_mmap_readn :: (pcm: *snd_pcm_t, buffer: **void, size: snd_pcm_uframes_t) -> snd_pcm_sframes_t #foreign alsa;

snd_device_name_hint :: (card: s32, iface: *u8, hints: ***void) -> s32 #foreign alsa;
snd_device_name_free_hint :: (hints: **void) -> s32 #foreign alsa;
snd_device_name_get_hint :: (hint: *void, id: *u8) -> *u8 #foreign alsa;


#if VERBOSE {
    check_hr :: (name: string) -> bool #expand {
        if `hr < 0 {
            log_error("% failed with code 0x%: %", name, formatInt(`hr, 16), sound_error_name(`hr)); // @Leak
            return false;
        }
        return true;
    }
}
else {
    check_hr :: (name: string) -> bool #expand {
        return `hr >= 0;
    }
}

default_device: *Input_Device;
current_device: *Input_Device;
