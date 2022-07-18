const std = @import("std");
const zCord = @import("zCord");

const WorkContext = @import("WorkContext.zig");
const util = @import("util.zig");

test {
    _ = WorkContext;
    _ = util;
}

const auto_restart = true;
//const auto_restart = std.builtin.mode == .Debug;

pub usingnamespace if (auto_restart) RestartHandler else struct {};

const RestartHandler = struct {
    pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
        std.debug.print("PANIC -- {s}\n", .{msg});

        if (error_return_trace) |t| {
            std.debug.dumpStackTrace(t.*);
        }

        std.debug.dumpCurrentStackTrace(@returnAddress());

        const err = std.os.execveZ(
            std.os.argv[0],
            @ptrCast([*:null]?[*:0]u8, std.os.argv.ptr),
            @ptrCast([*:null]?[*:0]u8, std.os.environ.ptr),
        );

        std.debug.print("{s}\n", .{@errorName(err)});
        std.os.exit(42);
    }
};

pub fn main() !void {
    try util.mapSigaction(struct {
        pub fn WINCH(signum: c_int) callconv(.C) void {
            _ = signum;
            WorkContext.reload();
        }

        pub fn USR1(signum: c_int) callconv(.C) void {
            _ = signum;
            const err = std.os.execveZ(
                std.os.argv[0],
                @ptrCast([*:null]?[*:0]u8, std.os.argv.ptr),
                @ptrCast([*:null]?[*:0]u8, std.os.environ.ptr),
            );

            std.debug.print("{s}\n", .{@errorName(err)});
        }
    });

    try zCord.root_ca.preload(std.heap.page_allocator);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    util.PoolString.prefill(16, struct {});

    var auth_buf: [0x100]u8 = undefined;
    const client = zCord.Client{
        .auth_token = try std.fmt.bufPrint(&auth_buf, "Bot {s}", .{std.os.getenv("DISCORD_AUTH") orelse return error.AuthNotFound}),
    };

    var gateway = try client.startGateway(.{
        .allocator = gpa.allocator(),
        .intents = .{ .guild_messages = true, .direct_messages = true, .message_content = true },
        .presence = .{
            .status = .online,
            .activities = &.{
                .{
                    .type = .Watching,
                    .name = "examples: %%666 or %%std.ArrayList",
                },
            },
        },
    });
    defer gateway.destroy();

    const work = try WorkContext.create(
        gpa.allocator(),
        client,
        std.os.getenv("ZIGLIB") orelse return error.ZiglibNotFound,
        std.os.getenv("GITHUB_AUTH"),
    );

    while (true) {
        const event = try gateway.recvEvent();
        defer event.deinit();
        processEvent(event, work) catch |err| {
            std.debug.print("{}\n", .{err});
        };
    }
}

pub fn processEvent(event: zCord.Gateway.Event, ctx: *WorkContext) !void {
    if (event.name != .message_create) return;

    var channel_id: ?zCord.Snowflake(.channel) = null;
    var source_msg_id: ?zCord.Snowflake(.message) = null;

    // If `channel_id` was guaranteed to exist before `content`, we wouldn't need to build this list :(
    var base: ?*util.PoolString = null;

    // This is needed to maintain insertion order. If we only used base, it would be in reverse order.
    var tail: *util.PoolString = undefined;

    defer while (base) |text| {
        base = text.next;
        text.destroy();
    };

    while (try event.data.objectMatch(enum { id, content, channel_id })) |match| switch (match.key) {
        .id => {
            source_msg_id = try zCord.Snowflake(.message).consumeJsonElement(match.value);
        },
        .channel_id => {
            channel_id = try zCord.Snowflake(.channel).consumeJsonElement(match.value);
        },
        .content => {
            const reader = try match.value.stringReader();
            while (try findAsk(reader)) |text| {
                text.next = null;
                if (base == null) {
                    base = text;
                    tail = text;
                } else {
                    tail.next = text;
                    tail = text;
                }
            }
            _ = try match.value.finalizeToken();
        },
    };

    if (channel_id != null and source_msg_id != null) {
        while (base) |text| {
            base = text.next;
            std.debug.print(">> %%{s}\n", .{text.array.slice()});
            if (ctx.ask_mailbox.putOverwrite(.{ .channel_id = channel_id.?, .source_msg_id = source_msg_id.?, .text = text })) |existing| {
                existing.text.destroy();
            }
        }
    }
}

fn findAsk(reader: anytype) !?*util.PoolString {
    const State = enum {
        no_match,
        percent,
        ready,
        endless,
    };
    var state = State.no_match;
    var string = try util.PoolString.create();
    errdefer string.destroy();

    while (reader.readByte()) |c| {
        switch (state) {
            .no_match => {
                if (c == '%') {
                    state = .percent;
                }
            },
            .percent => {
                state = if (c == '%') .ready else .no_match;
            },
            .ready => {
                switch (c) {
                    ' ', ',', '\n', '\t', ':', ';', '(', ')', '!', '?', '[', ']', '{', '}' => {
                        if (std.mem.eql(u8, string.array.slice(), "run")) {
                            state = .endless;
                            try string.array.append(c);
                        } else {
                            break;
                        }
                    },
                    else => try string.array.append(c),
                }
            },
            .endless => try string.array.append(c),
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    // Strip trailing period
    if (string.array.len > 0 and string.array.get(string.array.len - 1) == '.') {
        _ = string.array.pop();
    }
    if (string.array.len == 0) {
        string.destroy();
        return null;
    } else {
        return string;
    }
}
