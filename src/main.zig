const std = @import("std");
const c = @import("c.zig");

test "decode" {
    var decoder: ?*c.FLAC__StreamDecoder = null;
    var init_status: c.FLAC__StreamDecoderInitStatus = undefined;

    decoder = c.FLAC__stream_decoder_new();
    if (decoder == null) return error.AllocatingDecoder;
    defer c.FLAC__stream_decoder_delete(decoder);

    var user_data = UserData{};

    _ = c.FLAC__stream_decoder_set_md5_checking(decoder, 1);
    init_status = c.FLAC__stream_decoder_init_file(decoder, "blah", write_callback, metadata_callback, error_callback, &user_data);
    if (init_status != c.FLAC__STREAM_DECODER_INIT_STATUS_OK) return error.InitializingDecoder;

    const ok = c.FLAC__stream_decoder_process_until_end_of_stream(decoder);
    if (ok == 0) return error.NotOK;
    std.log.info("state: {s}", .{c.FLAC__StreamDecoderStateString[c.FLAC__stream_decoder_get_state(decoder)]});
}

const UserData = struct {
    total_samples: u64 = 0,
    sample_rate: usize = 0,
    channels: usize = 0,
    bps: usize = 0,
};

export fn write_callback(decoder: ?*const c.FLAC__StreamDecoder, frame_opt: ?*const c.FLAC__Frame, buffer_opt: ?[*]const ?[*]const c.FLAC__int32, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderWriteStatus {
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    const total_size = data.total_samples * data.channels * (data.bps / 8);
    _ = total_size;
    _ = decoder;
    const frame = frame_opt.?;
    const buffer = buffer_opt.?;

    if (data.total_samples == 0) return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    if (data.channels != 2 or data.bps != 16) return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    if (frame.header.channels != 2) return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    if (buffer[0] == null) return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    if (buffer[1] == null) return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;

    if (frame.header.number.sample_number == 0) {
        // TODO: write to file
    }

    var i: usize = 0;
    while (i < frame.header.blocksize) : (i += 1) {}

    return c.FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

export fn metadata_callback(decoder: ?*const c.FLAC__StreamDecoder, metadata_opt: ?*const c.FLAC__StreamMetadata, client_data: ?*anyopaque) void {
    _ = decoder;
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    const metadata = metadata_opt.?;
    if (metadata.type == c.FLAC__METADATA_TYPE_STREAMINFO) {
        data.total_samples = metadata.data.stream_info.total_samples;
        data.sample_rate = metadata.data.stream_info.sample_rate;
        data.channels = metadata.data.stream_info.channels;
        data.bps = metadata.data.stream_info.bits_per_sample;
    }
}

export fn error_callback(decoder: ?*const c.FLAC__StreamDecoder, status: c.FLAC__StreamDecoderErrorStatus, client_data: ?*anyopaque) void {
    _ = decoder;
    _ = client_data;

    std.log.err("Got error callback: {s}", .{c.FLAC__StreamDecoderErrorStatusString[status]});
}
