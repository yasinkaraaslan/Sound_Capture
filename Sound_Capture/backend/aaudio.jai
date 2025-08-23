#assert OS == .ANDROID;

// NOTE(Yasin): You have to add this line to your AndroidManifest.xml file
// <uses-permission android:name="android.permission.RECORD_AUDIO" />
// If you are using Toolchains/Android, it will refresh the manifest file every time you compile unfortunately.

android_request_audio_permission :: () {
    // Taken from Charles Taylor's Android module
    check_env_init();

    e := env.*;

    String   := e.FindClass(env, "java/lang/String");
    Activity := e.FindClass(env, "android/app/Activity");
    requestPermissions := e.GetMethodID(env, Activity, "requestPermissions", "([Ljava/lang/String;I)V");

    permission_jstring := e.NewStringUTF(env, ANDROID_AUDIO_PERMISSION);
    defer e.DeleteLocalRef(env, permission_jstring);

    // You have to pass an array of permissions, can't just pass one...
    permissions_array := e.NewObjectArray(env, 1, String, null);
    e.SetObjectArrayElement(env, permissions_array, 0, permission_jstring);

    request_code: s32 = 31; // Used to match this request in the onRequestPermissionsResult callback. We don't handle that callback so doesn't matter.


    args_array := jvalue.[ (cast(*jvalue)*permissions_array).*, (cast(*jvalue)*request_code).*];
    e.CallVoidMethodA(env, context.android_app.activity.clazz, requestPermissions, args_array.data);
}

android_has_audio_permission :: () -> bool {
    libandroid :: #system_library "libandroid";
    Posix :: #import "POSIX";

    APermissionManager_checkPermission :: (permission: *u8, pid: Posix.pid_t, uid: Posix.uid_t, result: *u32) -> s32 #foreign libandroid;

    PERMISSION_GRANTED :: 0;
    PERMISSION_DENIED :: -1;

    result: u32;
    APermissionManager_checkPermission(ANDROID_AUDIO_PERMISSION, Posix.getpid(), Posix.getuid(), *result);
    return result == PERMISSION_GRANTED;
}

// Make sure you that android_has_permission is true before initializing.
// Otherwise bad things will happen.
capture_init :: () {
    hr := AAudio_createStreamBuilder(*builder);
    check_hr("Create stream builder");

    AAudioStreamBuilder_setDirection(builder, xx AAUDIO_DIRECTION.INPUT);
    AAudioStreamBuilder_setSharingMode(builder, .SHARED);
    AAudioStreamBuilder_setPerformanceMode(builder, .LOW_LATENCY);
    AAudioStreamBuilder_setSampleRate(builder, SAMPLE_RATE);
    AAudioStreamBuilder_setChannelCount(builder, NUM_CHANNELS);
    AAudioStreamBuilder_setFormat(builder, .PCM_I16);

    hr = AAudioStreamBuilder_openStream(builder, *stream);
    check_hr("Open stream");
}

start_recording :: () {
    hr := AAudioStream_requestStart(stream);
    check_hr("Stream start");
}

stop_recording :: () {
    hr := AAudioStream_requestStop(stream);
    check_hr("Stream stop");
}

capture_deinit :: () {
    if stream {
        hr := AAudioStream_close(stream);
        check_hr("Stream close");
        stream = null;
    }

    if builder {
        hr := AAudioStreamBuilder_delete(builder);
        check_hr("Delete stream builder");
        builder = null;
    }
}

get_next_sound_buffer :: () -> []s16 {
    NUM_FRAMES :: 2048;
    buffer := NewArray(NUM_FRAMES * NUM_CHANNELS, s16,, temp);
    num_frames := AAudioStream_read(stream, buffer.data, NUM_FRAMES, 0);
    if num_frames < 0 {
        hr := num_frames;
        check_hr("Audio stream read");
        return .[];
    }
    if num_frames == 0 return .[];

    buffer.count = num_frames * NUM_CHANNELS;
    return buffer;
}


get_default_capture_device :: () -> Input_Device {
    // @Incomplete
    return .{};
}

refresh_capture_devices :: () {
    // @Incomplete
}

set_capture_device :: (device: *Input_Device) {
    hr := AAudioStream_close(stream);
    check_hr("Stream close");
    stream = null;

    id: s32 = cast(s32)device.internal_id;
    AAudioStreamBuilder_setDeviceId(builder, id);
    hr = AAudioStreamBuilder_openStream(builder, *stream);
    check_hr("Open stream");
}

#scope_file
env: *JNIEnv;
check_env_init :: inline () {
    if !env {
        vm := context.android_app.activity.vm;
        vm.*.AttachCurrentThread(vm, *env, null);
    }
}

check_hr :: (name: string) -> bool #expand {
    if `hr < 0 {
        log_error("% failed: %", name, to_string(AAudio_convertResultToText(xx `hr)));
        return false;
    }
    return true;
}

#import "Android/Jni";
#import "Android/AAudio";

builder: *AAudioStreamBuilder;
stream: *AAudioStream;

ANDROID_AUDIO_PERMISSION :: "android.permission.RECORD_AUDIO";
