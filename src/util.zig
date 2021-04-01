const std = @import("std");

/// Super simple "perfect hash" algorithm
/// Only really useful for switching on strings
// TODO: can we auto detect and promote the underlying type?
pub fn Swhash(comptime max_bytes: comptime_int) type {
    const T = std.meta.Int(.unsigned, max_bytes * 8);

    return struct {
        pub fn match(string: []const u8) T {
            return hash(string) orelse std.math.maxInt(T);
        }

        pub fn case(comptime string: []const u8) T {
            return hash(string) orelse @compileError("Cannot hash '" ++ string ++ "'");
        }

        fn hash(string: []const u8) ?T {
            if (string.len > max_bytes) return null;
            var tmp = [_]u8{0} ** max_bytes;
            std.mem.copy(u8, &tmp, string);
            return std.mem.readIntNative(T, &tmp);
        }
    };
}

pub fn boolMatcher(comptime size: comptime_int) @TypeOf(BoolMatcher(size).m) {
    return BoolMatcher(size).m;
}

pub fn BoolMatcher(comptime size: comptime_int) type {
    const T = std.meta.Int(.unsigned, size);
    return struct {
        pub fn m(array: [size]bool) T {
            var result: T = 0;
            comptime var i = 0;
            inline while (i < size) : (i += 1) {
                result |= @as(T, @boolToInt(array[i])) << i;
            }
            return result;
        }
    };
}

fn ReturnOf(comptime func: anytype) type {
    return @typeInfo(@TypeOf(func)).Fn.return_type.?;
}

pub fn Mailbox(comptime T: type) type {
    return struct {
        const Self = @This();

        value: ?T = null,
        cond: std.Thread.Condition = .{},
        mutex: std.Thread.Mutex = .{},

        pub fn get(self: *Self) T {
            const held = self.mutex.acquire();
            defer held.release();

            if (self.value) |value| {
                self.value = null;
                return value;
            } else {
                self.cond.wait(&self.mutex);

                defer self.value = null;
                return self.value.?;
            }
        }

        pub fn getWithTimeout(self: *Self, timeout_ns: u64) ?T {
            const held = self.mutex.acquire();
            defer held.release();

            if (self.value) |value| {
                self.value = null;
                return value;
            } else {
                const future_ns = std.time.nanoTimestamp() + timeout_ns;
                var future: std.os.timespec = undefined;
                future.tv_sec = @intCast(@TypeOf(future.tv_sec), @divFloor(future_ns, std.time.ns_per_s));
                future.tv_nsec = @intCast(@TypeOf(future.tv_nsec), @mod(future_ns, std.time.ns_per_s));

                const rc = std.os.system.pthread_cond_timedwait(&self.cond.impl.cond, &self.mutex.impl.pthread_mutex, &future);
                std.debug.assert(rc == 0 or rc == std.os.system.ETIMEDOUT);
                defer self.value = null;
                return self.value;
            }
        }

        pub fn putOverwrite(self: *Self, value: T) void {
            self.value = value;
            self.cond.impl.signal();
        }
    };
}
