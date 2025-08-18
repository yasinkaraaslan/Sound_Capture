main :: () {
    capture_init();
    defer capture_deinit();

    default_device := get_default_capture_device(); // This is selected automatically
    log("Selected: %", default_device.name);

    start_recording();

    buffer: [..]s16;
    while true {
        reset_temporary_storage();

        next_buffer := get_next_sound_buffer();
        array_add(*buffer, ..next_buffer);
        if seconds_since_init() > 5 { // Record for 5 seconds.
            stop_recording();
            write_to_wav(buffer, "output.wav");
            return;
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

    if !write_entire_file(file_name, *sb) {
        log_error("Error saving to file: '%'!", file_name);
    }
    else {
        log("Saved to file '%'", file_name);
    }
}

append_4 :: (sb: *String_Builder, num: u32) {
    append_by_pointer(sb, *num);
}

append_2 :: (sb: *String_Builder, num: u16) {
    append_by_pointer(sb, *num);
}

#import "File";
#import "Basic";
#import,dir "../../Sound_Capture";
