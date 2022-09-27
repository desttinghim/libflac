const std = @import("std");
pub const c = @import("c.zig");

/// T must be a struct defining the following:
/// - readCallback()
/// - seekCallback()
/// - tellCallback()
/// - lengthCallback()
/// - eofCallback()
/// - writeCallback()
/// - metadataCallback()
/// - errorCallback()
pub fn FLACDecoder(T: type) type {
    // TODO: check that T conforms
    return struct {
        export fn CallbackRead(decoder: ?*c.FLAC__StreamDecoder, buffer: ?[*]c.FLAC__byte, bytes: ?*usize, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderReadStatus {
            const t = @ptrCast(T, @alignCast(@alignOf(T), client_data));
            const slice = buffer.?[0..bytes.?];
            t.readCallback(decoder.?, slice) catch |e| switch (e) {
                error.EndOfStream => return c.FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM,
                error.Abort => return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT,
            };
            return c.FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
        }

        export fn CallbackSeek(decoder: ?*c.FLAC__StreamDecoder, buffer: ?[*]c.FLAC__byte, bytes: ?*usize, client_data: ?*anyopaque) callconv(.C) c.FLAC__StreamDecoderSeekStatus {
            const t = @ptrCast(T, @alignCast(@alignOf(T), client_data));
            const slice = buffer.?[0..bytes.?];
            t.readCallback(decoder.?, slice) catch |e| switch (e) {
                error.EndOfStream => return c.FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM,
                error.Abort => return c.FLAC__STREAM_DECODER_READ_STATUS_ABORT,
            };
            return c.FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
        }
    };
}

pub const DecoderVTable = struct {
    callback_read: *const fn (*c.FLAC__StreamDecoder, []u8, *DecoderVTable) ReadCallbackError!void,
    callback_seek: *const fn (*c.FLAC__StreamDecoder, u64, *DecoderVTable) SeekCallbackError!void,
    callback_tell: *const fn (*c.FLAC__StreamDecoder, *DecoderVTable) TellCallbackError!u64,
    callback_length: *const fn (*c.FLAC__StreamDecoder, *DecoderVTable) LengthCallbackError!u64,
    callback_eof: *const fn (*c.FLAC__StreamDecoder, *DecoderVTable) LengthCallbackError!void,
    callback_write: *const fn (*c.FLAC__StreamDecoder, *c.FLAC__Frame, []i32, *DecoderVTable) WriteCallbackError!void,
    callback_error: *const fn (*c.FLAC__StreamDecoder, []u8, *DecoderVTable) void,
};

pub const ReadCallbackError = error{
    EndOfStream,
    Abort,
};

pub const SeekCallbackError = error{
    Error,
    Unsupported,
};

pub const TellCallbackError = error{
    Error,
    Unsupported,
};

pub const LengthCallbackError = error{
    Error,
    Unsupported,
};

pub const WriteCallbackError = error{
    Abort,
};

pub const StreamDecoderError = error{
    LostSync,
    BadHeader,
    FrameCrcMismatch,
    UnparseableStream,
    BadMetadata,
};
