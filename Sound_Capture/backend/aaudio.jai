#assert OS == .ANDROID;

// NOTE(Yasin): You have to add this line to your AndroidManifest.xml file
// <uses-permission android:name="android.permission.RECORD_AUDIO" />
// If you are using Toolchains/Android, it will refresh the manifest file every time you compile unfortunately.

// Make sure that android_has_audio_permission is true before initializing.
// Otherwise, bad things will happen.

android_request_audio_permission :: () {
    // Taken from Charles Taylor's Android module
    check_env_init();

    String   := e.FindClass(env, "java/lang/String");
    Activity := e.FindClass(env, "android/app/Activity");
    requestPermissions := e.GetMethodID(env, Activity, "requestPermissions", "([Ljava/lang/String;I)V");

    permission_jstring := to_j_string(ANDROID_AUDIO_PERMISSION);

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


get_default_capture_device :: () -> *Input_Device {
    return default_device;
}

refresh_capture_devices :: () {
    for * sound_capture_devices {
        free_device(it);
    }
    array_reset(*sound_capture_devices);

    check_env_init();

    getDevices := e.GetMethodID(env, AudioManager, "getDevices", "(I)[Landroid/media/AudioDeviceInfo;");


    GET_DEVICES_INPUTS :: 1;

    device_array := e.CallObjectMethod(env, audio_manager, getDevices, GET_DEVICES_INPUTS);
    count := e.GetArrayLength(env, device_array);

    array_reserve(*sound_capture_devices, count);

    getId := e.GetMethodID(env, AudioDeviceInfo, "getId", "()I");
    getProductName := e.GetMethodID(env, AudioDeviceInfo, "getProductName", "()Ljava/lang/CharSequence;");

    CharSequence := e.FindClass(env, "java/lang/CharSequence");
    toString := e.GetMethodID(env, CharSequence, "toString", "()Ljava/lang/String;");

    for 0..count-1 {
        device_info := e.GetObjectArrayElement(env, device_array, it);

        id := e.CallIntMethod(env, device_info, getId);
        char_seq := e.CallObjectMethod(env, device_info, getProductName);

        j_string := e.CallObjectMethod(env, char_seq, toString);


        device := array_add(*sound_capture_devices);
        device.internal_id = cast(*void)id;
        device.name = from_j_string(j_string);

        if it == 0 {
            // We are guessing that the first one is the default one, though this isn't documented.
            // The actual way of getting the default device is much more complicated but we don't go that route.
            default_device = device;
        }
    }
}

set_capture_device :: (device: Input_Device) {
    if stream {
        hr := AAudioStream_close(stream);
        check_hr("Stream close");
        stream = null;
    }

    id := cast(s32)device.internal_id;
    AAudioStreamBuilder_setDeviceId(builder, id);
    hr := AAudioStreamBuilder_openStream(builder, *stream);
    check_hr("Open stream");
}

#scope_module
backend_init :: () {
    hr := AAudio_createStreamBuilder(*builder);
    check_hr("Create stream builder");

    AAudioStreamBuilder_setDirection(builder, xx AAUDIO_DIRECTION.INPUT);
    AAudioStreamBuilder_setSharingMode(builder, .SHARED);
    AAudioStreamBuilder_setPerformanceMode(builder, .LOW_LATENCY);
    AAudioStreamBuilder_setSampleRate(builder, SAMPLE_RATE);
    AAudioStreamBuilder_setChannelCount(builder, NUM_CHANNELS);
    AAudioStreamBuilder_setFormat(builder, .PCM_I16);
}

#scope_file
free_device :: (using device: *Input_Device) {
    if name free(name);

    internal_id = null;
    internal_data = null;
}

env: *JNIEnv;
audio_manager: jobject;
AudioDeviceInfo: jclass;
AudioManager: jclass;
AndroidContext: jclass;


to_j_string :: (s: string) -> jstring #expand {
    j := env.*.NewStringUTF(env, temp_c_string(s));
    `defer env.*.DeleteLocalRef(env, j);
    return j;
}

from_j_string :: (j: jstring) -> string #expand {
    c_string := env.*.GetStringUTFChars(env, j, null);
    `defer env.*.ReleaseStringUTFChars(env, j, c_string);
    return copy_string(to_string(c_string));
}

check_env_init :: () #expand {
    if !env {
        vm := context.android_app.activity.vm;
        vm.*.AttachCurrentThread(vm, *env, null);
        AudioDeviceInfo = env.*.FindClass(env, "android/media/AudioDeviceInfo");
        AndroidContext = env.*.FindClass(env, "android/content/Context");
        AudioManager = env.*.FindClass(env, "android/media/AudioManager");

        audio_jstring := to_j_string("audio");

        getSystemService := env.*.GetMethodID(env, AndroidContext, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
        audio_manager = env.*.CallObjectMethod(env, context.android_app.activity.clazz, getSystemService, audio_jstring);

    }
    `e := env.*;
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

default_device: *Input_Device;

ANDROID_AUDIO_PERMISSION :: "android.permission.RECORD_AUDIO";
