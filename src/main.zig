const std = @import("std");
const zCord = @import("zCord");

const WorkContext = @import("WorkContext.zig");

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
    std.os.sigaction(
        std.os.SIGWINCH,
        &std.os.Sigaction{
            .handler = .{
                .handler = struct {
                    fn handler(signum: c_int) callconv(.C) void {
                        _ = signum;
                        WorkContext.reload();
                    }
                }.handler,
            },
            .mask = std.os.empty_sigset,
            .flags = 0,
        },
        null,
    );

    std.os.sigaction(
        std.os.SIGUSR1,
        &std.os.Sigaction{
            .handler = .{
                .handler = struct {
                    fn handler(signum: c_int) callconv(.C) void {
                        _ = signum;
                        const err = std.os.execveZ(
                            std.os.argv[0],
                            @ptrCast([*:null]?[*:0]u8, std.os.argv.ptr),
                            @ptrCast([*:null]?[*:0]u8, std.os.environ.ptr),
                        );

                        std.debug.print("{s}\n", .{@errorName(err)});
                    }
                }.handler,
            },
            .mask = std.os.empty_sigset,
            .flags = 0,
        },
        null,
    );

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

            const match = try zCord.json.path.match(data, struct {
                @"id": zCord.Snowflake(.message),
                @"channel_id": zCord.Snowflake(.channel),
                @"content": zCord.json.path.Wrap(std.BoundedArray(u8, 0x1000), findAsk),
            });

            if (match.@"content".data.len > 0) {
                std.debug.print(">> %%{s}\n", .{match.@"content".data.constSlice()});
                ctx.ask_mailbox.putOverwrite(.{ .channel_id = match.@"channel_id", .source_msg_id = match.@"id", .text = match.@"content".data });
            }
        }

        fn findAsk(elem: zCord.JsonElement) !std.BoundedArray(u8, 0x1000) {
            const State = enum {
                no_match,
                percent,
                ready,
                endless,
            };
            var state = State.no_match;
            var array = std.BoundedArray(u8, 0x1000).init(0) catch unreachable;

            var reader = try elem.stringReader();

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
                            ' ', ',', '\n', '\t', '(', ')', '!', '?', '[', ']', '{', '}' => {
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
            return array;
        }
    }) catch |err| switch (err) {
        error.AuthenticationFailed => |e| return e,
        else => @panic(@errorName(err)),
    };
}
