// This example records audio for 5 seconds and saves it to a .wav file.

main :: () {
    #if OS == .ANDROID {
        // You have to add this line to your AndroidManifest.xml file
        // <uses-permission android:name="android.permission.RECORD_AUDIO" />
        android_request_audio_permission();

        // This is a quick and dirty way to wait for the permission to be answered.
        // You would want to do something more sophisticated in the real world.

        time := 0;
        while !android_has_audio_permission() {
            sleep_milliseconds(50);
            time += 50;
            if time > 5000 { // 5 seconds
                exit(1);
            }
        };
    }

    capture_init();
    defer capture_deinit();

    default_device := get_default_capture_device(); // This is selected automatically
    log("Selected: %", default_device.name);

    start_recording();
    start := seconds_since_init();
    buffer: [..]s16;

    while true {
        reset_temporary_storage();
        #if OS == .ANDROID {
            Input.android_process_events(); // To make sure we don't go into 'not responding' state
        }

        next_buffer := get_next_sound_buffer();
        array_add(*buffer, ..next_buffer);
        if seconds_since_init() - start > 5 { // Record for 5 seconds.
            stop_recording();

            #if OS == .ANDROID {
                // You can go to Android/data/com.my_domain.whatever/files/ to see the file.
                data_path := to_string(context.android_app.activity.externalDataPath);
                path := tprint("%/output.wav", data_path);
            }
            else {
                path := "output.wav";
            }
            write_to_wav(buffer, path);
            exit(0);
        }
    }
}

write_to_wav :: (buffer: []s16, file_name: string) {
    subchunk2_size: u32 = cast(u32)buffer.count * BIT_DEPTH / 8;
    chunk_size: u32 = 36 + subchunk2_size;

    sb: String_Builder;

    append(*sb, "RIFF");
    append_4(*sb, chunk_size);
    append(*sb, "WAVE");

    append(*sb, "fmt ");
    append_4(*sb, 16); // PCM
    append_2(*sb, 1); // PCM
    append_2(*sb, NUM_CHANNELS);
    append_4(*sb, SAMPLE_RATE);
    append_4(*sb, SAMPLE_RATE * BLOCK_ALIGN);
    append_2(*sb, BLOCK_ALIGN);
    append_2(*sb, BIT_DEPTH);

    append(*sb, "data");
    append_4(*sb, subchunk2_size);
    append(*sb, cast(*u8)buffer.data, buffer.count*size_of(s16));

    if write_entire_file(file_name, *sb) {
        log("Saved to file '%'", file_name);
    }
}

append_4 :: (sb: *String_Builder, num: u32) {
    append_by_pointer(sb, *num);
}

append_2 :: (sb: *String_Builder, num: u16) {
    append_by_pointer(sb, *num);
}
#if OS == .ANDROID #import "Android"()(main);

#import "File";
#import "Basic";
#import,dir "../../Sound_Capture";
