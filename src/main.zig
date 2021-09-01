const std = @import("std");
const zCord = @import("zCord");

const WorkContext = @import("WorkContext.zig");
const util = @import("util.zig");

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
    util.mapSigaction(struct {
        pub fn SIGWINCH() void {
            WorkContext.reload();
        }

        pub fn SIGUSR1() void {
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

    var auth_buf: [0x100]u8 = undefined;
    const client = try zCord.Client.create(.{
        .allocator = &gpa.allocator,
        .auth_token = try std.fmt.bufPrint(&auth_buf, "Bot {s}", .{std.os.getenv("DISCORD_AUTH") orelse return error.AuthNotFound}),
        .intents = .{ .guild_messages = true, .direct_messages = true },
        .presence = .{
            .status = .online,
            .activities = &.{
                .{
                    .type = .Game,
                    .name = "examples: %%666 or %%std.ArrayList",
                },
            },
        },
    });
    defer client.destroy();

    const work = try WorkContext.create(
        &gpa.allocator,
        client,
        std.os.getenv("ZIGLIB") orelse return error.ZiglibNotFound,
        std.os.getenv("GITHUB_AUTH"),
    );

    client.ws(work, struct {
        pub fn handleDispatch(ctx: *WorkContext, name: []const u8, data: zCord.JsonElement) !void {
            if (!std.mem.eql(u8, name, "MESSAGE_CREATE")) return;

            var channel_id: ?zCord.Snowflake(.channel) = null;
            var source_msg_id: ?zCord.Snowflake(.message) = null;
            var texts = std.BoundedArray(std.BoundedArray(u8, 0x1000), 8).init(0) catch unreachable;

            while (try data.objectMatch(enum { id, content, channel_id })) |match| switch (match) {
                .id => |e_id| {
                    source_msg_id = try zCord.Snowflake(.message).consumeJsonElement(e_id);
                    _ = try e_id.finalizeToken();
                },
                .channel_id => |e_channel_id| {
                    channel_id = try zCord.Snowflake(.channel).consumeJsonElement(e_channel_id);
                    _ = try e_channel_id.finalizeToken();
                },
                .content => |e_content| {
                    const reader = try e_content.stringReader();
                    while (try findAsk(reader)) |text| {
                        texts.append(text) catch break;
                    }
                    _ = try e_content.finalizeToken();
                },
            };

            if (channel_id != null and source_msg_id != null) {
                for (texts.constSlice()) |text| {
                    std.debug.print(">> %%{s}\n", .{text.constSlice()});
                    ctx.ask_mailbox.putOverwrite(.{ .channel_id = channel_id.?, .source_msg_id = source_msg_id.?, .text = text });
                }
            }
        }

        fn findAsk(reader: anytype) !?std.BoundedArray(u8, 0x1000) {
            const State = enum {
                no_match,
                percent,
                ready,
                endless,
            };
            var state = State.no_match;
            var array = std.BoundedArray(u8, 0x1000).init(0) catch unreachable;

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
                                if (std.mem.eql(u8, array.constSlice(), "run")) {
                                    state = .endless;
                                    try array.append(c);
                                } else {
                                    break;
                                }
                            },
                            else => try array.append(c),
                        }
                    },
                    .endless => try array.append(c),
                }
            } else |err| switch (err) {
                error.EndOfStream => {},
                else => |e| return e,
            }

            // Strip trailing period
            if (array.len > 0 and array.get(array.len - 1) == '.') {
                _ = array.pop();
            }
            return if (array.len == 0) null else array;
        }
    }) catch |err| switch (err) {
        error.AuthenticationFailed => |e| return e,
        else => @panic(@errorName(err)),
    };
}
