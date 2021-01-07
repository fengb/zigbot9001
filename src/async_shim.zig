const std = @import("std");

pub usingnamespace switch (std.io.mode) {
    .evented => native,
    .blocking => shims,
};

const native = struct {
    pub const FileWriter = std.fs.File.Writer;
    pub const FileReader = std.fs.File.Reader;
    pub const fileWriter = std.fs.File.writer;
    pub const fileReader = std.fs.File.reader;
};

const shims = struct {
    pub const FileWriter = std.io.Writer(
        std.fs.File,
        std.os.WriteError,
        struct {
            fn asyncWrite(self: std.fs.File, bytes: []const u8) std.os.WriteError!usize {
                return std.event.Loop.instance.?.write(self.handle, bytes, false);
            }
        }.asyncWrite,
    );

    pub fn fileWriter(file: std.fs.File) FileWriter {
        return .{ .context = file };
    }

    pub const FileReader = std.io.Reader(
        std.fs.File,
        std.os.ReadError,
        struct {
            fn asyncRead(self: std.fs.File, bytes: []u8) std.os.ReadError!usize {
                return std.event.Loop.instance.?.read(self.handle, bytes, false);
            }
        }.asyncRead,
    );

    pub fn fileReader(file: std.fs.File) FileReader {
        return .{ .context = file };
    }
};
