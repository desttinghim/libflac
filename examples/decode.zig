const std = @import("std");
const flac = @import("flac");
const c = flac.c;

const version = "0.0.1";

pub fn main() !void {
    // Allocation
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // Variables
    var decoder: ?*c.FLAC__StreamDecoder = null;
    var init_status: c.FLAC__StreamDecoderInitStatus = undefined;
    const stdout_handle = std.io.getStdOut();
    defer stdout_handle.close();
    const stdout = stdout_handle.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        try stdout.print("version {s}\n", .{version});
        try stdout.print("usage: {s} infile.flac outfile.wav\n", .{args[0]});
        return;
    }

    const cwd = std.fs.cwd();
    const in_filename = args[1];
    const out_filename = args[2];

    // Create a new stream decoder
    decoder = c.FLAC__stream_decoder_new();
    if (decoder == null) return error.AllocatingDecoder;
    defer c.FLAC__stream_decoder_delete(decoder);

    // Initialize user data struct to use in callbacks
    var user_data = UserData{
        // Open input file
        .in = try cwd.openFile(in_filename, .{}),
        // Open output file
        .out = try cwd.createFile(out_filename, .{}),
    };
    defer user_data.out.close();
    defer user_data.in.close();

    _ = c.FLAC__stream_decoder_set_md5_checking(decoder, 1);

    init_status = c.FLAC__stream_decoder_init_stream(
        decoder,
        read_callback,
        seek_callback,
        tell_callback,
        length_callback,
        eof_callback,
        write_callback,
        metadata_callback,
        error_callback,
        &user_data,
    );
    if (init_status != c.FLAC__STREAM_DECODER_INIT_STATUS_OK) return error.InitializingDecoder;

    const ok = c.FLAC__stream_decoder_process_until_end_of_stream(decoder) != 0;
    try stdout.print("decoding: {s}", .{if (ok) "succeeded" else "FAILED"});
}

const UserData = struct {
    in: std.fs.File,
    out: std.fs.File,
    total_samples: u64 = 0,
    sample_rate: u32 = 0,
    channels: u32 = 0,
    bps: u32 = 0,
};

export fn read_callback(decoder: ?*const c.FLAC__StreamDecoder, buffer_opt: ?[*]c.FLAC__byte, bytes_opt: ?*usize, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderReadStatus {
    _ = decoder;
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    var reader = data.in.reader();
    var bytes_ptr = bytes_opt orelse return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT;
    var buffer = buffer_opt.?[0..bytes_ptr.*];
    bytes_ptr.* = reader.read(buffer) catch return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT;
    if (bytes_ptr.* == 0) return c.FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM;
    return c.FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
}
export fn seek_callback(decoder: ?*const c.FLAC__StreamDecoder, absolute_byte_offset: u64, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderSeekStatus {
    _ = decoder;
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));

    data.in.seekTo(absolute_byte_offset) catch {
        return c.FLAC__STREAM_DECODER_SEEK_STATUS_ERROR;
    };
    return c.FLAC__STREAM_DECODER_SEEK_STATUS_OK;
}
export fn tell_callback(decoder: ?*const c.FLAC__StreamDecoder, absolute_byte_offset: ?*u64, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderTellStatus {
    _ = decoder;
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    absolute_byte_offset.?.* = data.in.getPos() catch return c.FLAC__STREAM_DECODER_TELL_STATUS_ERROR;
    return c.FLAC__STREAM_DECODER_TELL_STATUS_OK;
}
export fn length_callback(decoder: ?*const c.FLAC__StreamDecoder, stream_length: ?*u64, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderLengthStatus {
    _ = decoder;
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    stream_length.?.* = data.in.getEndPos() catch return c.FLAC__STREAM_DECODER_LENGTH_STATUS_ERROR;
    return c.FLAC__STREAM_DECODER_LENGTH_STATUS_OK;
}
export fn eof_callback(decoder: ?*const c.FLAC__StreamDecoder, client_data: ?*anyopaque) callconv(.C) c.FLAC__bool {
    _ = decoder;
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    const pos = data.in.getPos() catch return 1;
    const end_pos = data.in.getEndPos() catch return 1;
    return @boolToInt(pos == end_pos);
}

export fn write_callback(decoder: ?*const c.FLAC__StreamDecoder, frame_opt: ?*const c.FLAC__Frame, buffer_opt: ?[*]const ?[*]const c.FLAC__int32, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderWriteStatus {
    const data = @ptrCast(*UserData, @alignCast(@alignOf(UserData), client_data.?));
    const total_size = data.total_samples * data.channels * (data.bps / 8);
    _ = decoder;
    const frame = frame_opt.?;
    const buffer = buffer_opt.?;

    if (data.total_samples == 0) {
        std.log.err("this example only works for FLAC files that have a total_samples count in STREAMINFO", .{});
        return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }
    if (data.channels != 2 or data.bps != 16) {
        std.log.err("this example only supports 16bit stereo streams", .{});
        return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }
    if (frame.header.channels != 2) {
        std.log.err("This frame contains {} channels (should be 2)", .{frame.header.channels});
        return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }
    if (buffer[0] == null) {
        std.log.err("buffer [0] is NULL", .{});
        return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }
    if (buffer[1] == null) {
        std.log.err("buffer [1] is NULL", .{});
        return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
    }

    const writer = data.out.writer();
    if (frame.header.number.sample_number == 0) {
        const wav_opt = WavOpt{
            .data = data,
            .total_size = @intCast(u32, total_size),
        };
        write_wav_header(wav_opt, writer) catch {
            std.log.err("write error", .{});
            return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        };
    }

    var i: usize = 0;
    while (i < frame.header.blocksize) : (i += 1) {
        write_buffer(buffer, i, writer) catch {
            std.log.err("write error", .{});
            return c.FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
        };
    }

    return c.FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

fn write_buffer(buffer: [*]const ?[*]const i32, i: usize, writer: anytype) !void {
    try writer.writeInt(i16, @intCast(i16, buffer[0].?[i]), .Little);
    try writer.writeInt(i16, @intCast(i16, buffer[1].?[i]), .Little);
}

const WavOpt = struct {
    data: *const UserData,
    total_size: u32,
};

fn write_wav_header(opt: WavOpt, writer: anytype) !void {
    _ = try writer.write("RIFF");
    try writer.writeInt(u32, opt.total_size + 36, .Little);
    _ = try writer.write("WAVEfmt ");
    try writer.writeInt(u32, 16, .Little);
    try writer.writeInt(u16, 1, .Little);
    try writer.writeInt(u16, @intCast(u16, opt.data.channels), .Little);
    try writer.writeInt(u32, opt.data.sample_rate, .Little);
    try writer.writeInt(u32, opt.data.sample_rate * opt.data.channels * (opt.data.bps / 8), .Little);
    try writer.writeInt(u16, @intCast(u16, opt.data.channels * (opt.data.bps / 8)), .Little);
    try writer.writeInt(u16, @intCast(u16, opt.data.bps), .Little);
    _ = try writer.write("data");
    try writer.writeInt(u32, opt.total_size, .Little);
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

        std.log.info("sample rate    : {} Hz", .{data.sample_rate});
        std.log.info("channels       : {}", .{data.channels});
        std.log.info("bits per sample: {}", .{data.bps});
        std.log.info("total samples  : {}", .{data.total_samples});
    }
}

export fn error_callback(decoder: ?*const c.FLAC__StreamDecoder, status: c.FLAC__StreamDecoderErrorStatus, client_data: ?*anyopaque) void {
    _ = decoder;
    _ = client_data;

    std.log.err("Got error callback: {}", .{status});
}
