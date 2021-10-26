const std = @import("std");
const zCord = @import("zCord");
const analBuddy = @import("analysis-buddy");

const format = @import("format.zig");
const util = @import("util.zig");

const WorkContext = @This();

allocator: *std.mem.Allocator,
zcord_client: *zCord.Client,
github_auth_token: ?[]const u8,
prng: std.rand.DefaultPrng,
prepared_anal: analBuddy.PrepareResult,
last_reload: usize,

timer: std.time.Timer,

ask_mailbox: util.Mailbox(Ask, 16),
ask_thread: std.Thread,

var reload_counter: usize = 0;

pub fn reload() void {
    reload_counter += 1;
}

pub const Ask = struct {
    text: *util.PoolString,
    channel_id: zCord.Snowflake(.channel),
    source_msg_id: zCord.Snowflake(.message),
};

pub fn create(allocator: *std.mem.Allocator, zcord_client: *zCord.Client, ziglib: []const u8, github_auth_token: ?[]const u8) !*WorkContext {
    const result = try allocator.create(WorkContext);
    errdefer allocator.destroy(result);

    result.allocator = allocator;
    result.zcord_client = zcord_client;
    result.github_auth_token = github_auth_token;
    result.prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp()));
    result.prepared_anal = try analBuddy.prepare(allocator, ziglib);
    errdefer result.prepared_anal.deinit();
    result.last_reload = reload_counter;

    result.timer = try std.time.Timer.start();

    result.ask_mailbox = .{};
    result.ask_thread = try std.Thread.spawn(.{}, askHandler, .{result});

    return result;
}

pub fn askHandler(self: *WorkContext) void {
    while (true) {
        const ask = self.ask_mailbox.get();
        self.askOne(ask) catch |err| {
            std.debug.print("{s}\n", .{err});
        };
    }
}

pub fn askOne(self: *WorkContext, ask: Ask) !void {
    const swh = util.Swhash(16);
    const ask_text = ask.text.array.slice();
    defer ask.text.destroy();

    switch (swh.match(ask_text)) {
        swh.case("status") => {
            const rusage = std.os.getrusage(std.os.system.RUSAGE_SELF);
            const cpu_sec = (rusage.utime.tv_sec + rusage.stime.tv_sec) * 1000;
            const cpu_us = @divFloor(rusage.utime.tv_usec + rusage.stime.tv_usec, 1000);

            var buf: [0x1000]u8 = undefined;
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "",
                .description = &.{
                    std.fmt.bufPrint(
                        &buf,
                        \\```
                        \\Uptime:    {}
                        \\CPU time:  {}
                        \\Max RSS:      {:.3}
                        \\```
                    ,
                        .{
                            format.time(@intCast(i64, self.timer.read() / std.time.ns_per_ms)),
                            format.time(cpu_sec + cpu_us),
                            std.fmt.fmtIntSizeBin(@intCast(u64, rusage.maxrss)),
                        },
                    ) catch unreachable,
                },
            });
            return;
        },
        swh.case("zen") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "For Great Justice",
                .description = &.{
                    \\```
                    \\A. Communicate intent precisely.
                    \\B. Edge cases matter.
                    \\C. Favor reading code over writing code.
                    \\D. Only one obvious way to do things.
                    \\E. Runtime crashes are better than bugs.
                    \\F. Compile errors are better than runtime crashes.
                    \\G. Incremental improvements.
                    \\H. Avoid local maximums.
                    \\I. Reduce the amount one must remember.
                    \\J. Focus on code rather than style.
                    \\K. Resource allocation may fail; resource deallocation must succeed.
                    \\L. Memory is a resource.
                    \\M. Together we serve the users.
                    \\```
                },
            });
            return;
        },
        swh.case("zenlang"),
        swh.case("v"),
        swh.case("vlang"),
        => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "bruh",
            });
            return;
        },
        swh.case("u0") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "Zig's billion dollar mistake™",
                .description = &.{"https://github.com/ziglang/zig/issues/1530#issuecomment-422113755"},
            });
            return;
        },
        swh.case("tater") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "",
                .image = "https://memegenerator.net/img/instances/41913604.jpg",
            });
            return;
        },
        swh.case("5076"), swh.case("ziglang/zig#5076") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .color = .green,
                .title = "ziglang/zig — issue #5076",
                .description = &.{
                    \\~~[syntax: drop the `const` keyword in global scopes](https://github.com/ziglang/zig/issues/5076)~~
                    \\https://www.youtube.com/watch?v=880uR25pP5U
                },
            });
            return;
        },
        swh.case("submodule"), swh.case("submodules") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "git submodules are the devil — _andrewrk_",
                .description = &.{"https://github.com/ziglang/zig-bootstrap/issues/17#issuecomment-609980730"},
            });
            return;
        },
        swh.case("2.718"), swh.case("2.71828") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "",
                .image = "https://camo.githubusercontent.com/7f0d955df2205a170bf1582105c319ec6b00ec5c/68747470733a2f2f692e696d67666c69702e636f6d2f34646d7978702e6a7067",
            });
            return;
        },
        swh.case("bruh") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "",
                .image = "https://user-images.githubusercontent.com/106511/86198112-6718ba00-bb46-11ea-92fd-d006b462c5b1.jpg",
            });
            return;
        },
        swh.case("dab") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "I promised I would dab and say “bruh” — _andrewrk_",
                .description = &.{"https://vimeo.com/492676992"},
                .image = "https://user-images.githubusercontent.com/219422/138796179-983cfd79-646e-4293-b46b-412ef0485101.jpg",
            });
            return;
        },
        swh.case("stage1") => {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = "",
                .image = "https://user-images.githubusercontent.com/219422/138794956-0f355d35-f99a-462c-a363-8b58f4e38c0e.png",
            });
            return;
        },
        else => {},
    }

    if (std.mem.startsWith(u8, ask_text, "run")) {
        const run = self.parseRun(ask_text) catch |e| switch (e) {
            error.InvalidInput => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = ask.channel_id,
                    .target_msg_id = .{ .reply = ask.source_msg_id },
                    .title = "Error - expected format:",
                    .description = &.{
                        \\%%run \`\`\`
                        \\// write your code here
                        \\\`\`\`
                    },
                });
                return;
            },
        };

        const has_fns = std.mem.indexOf(u8, run, "fn ") != null;
        const has_import_std = std.mem.indexOf(u8, run, "@import(\"std\")") != null;

        const msg_id = try self.sendDiscordMessage(.{
            .channel_id = ask.channel_id,
            .target_msg_id = .{ .reply = ask.source_msg_id },
            .title = "*Run pending...*",
            .description = &.{},
        });

        const import_std = "const std = @import(\"std\");\n";
        const fn_main = "pub fn main() anyerror!void {\n";
        const fn_main_end = "  }\n";

        const b = comptime util.boolMatcher(2);
        const segments = switch (b(.{ has_import_std, has_fns })) {
            b(.{ false, false }) => &[_][]const u8{ import_std, fn_main, run, fn_main_end },
            b(.{ false, true }) => &[_][]const u8{ import_std, run },
            b(.{ true, false }) => &[_][]const u8{ fn_main, run, fn_main_end },
            b(.{ true, true }) => &[_][]const u8{run},
        };

        var stdout_buffer: [1024]u8 = undefined;
        var stderr_buffer: [1024]u8 = undefined;
        const ran = self.requestRun(segments, stdout_buffer[3..1021], stderr_buffer[3..1000]) catch |e| {
            const output = switch (e) {
                error.TooManyRequests => "***Too many requests***",
                else => "***Unknown error***",
            };

            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .edit = msg_id },
                .title = "Run error",
                .description = &.{output},
            });
            return e;
        };

        const all_fields = [_]EmbedField{
            .{ .name = "stdout", .value = wrapString(ran.stdout, "```") },
            .{ .name = "stderr", .value = wrapString(ran.stderr, "```") },
        };
        const fields = switch (b(.{ ran.stdout.len > 0, ran.stderr.len > 0 })) {
            b(.{ false, false }) => &[0]EmbedField{},
            b(.{ true, false }) => all_fields[0..1],
            b(.{ false, true }) => all_fields[1..],
            b(.{ true, true }) => all_fields[0..],
        };

        _ = try self.sendDiscordMessage(.{
            .channel_id = ask.channel_id,
            .target_msg_id = .{ .edit = msg_id },
            .title = "Run Results",
            .description = if (fields.len == 0) &[_][]const u8{"***No Output***"} else &.{},
            .fields = fields,
        });
        return;
    }

    if (try self.maybeGithubIssue(ask_text)) |issue| {
        const is_pull_request = std.mem.indexOf(u8, issue.html_url.constSlice(), "/pull/") != null;
        const label = if (is_pull_request) "pull" else "issue";

        const repo = if (std.mem.indexOfScalar(u8, ask_text, '#')) |pound|
            ask_text[0..pound]
        else
            "ziglang/zig";

        var title_buf: [0x1000]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buf, "{s} — {s} #{d}", .{
            repo,
            label,
            issue.number,
        });
        _ = try self.sendDiscordMessage(.{
            .channel_id = ask.channel_id,
            .target_msg_id = .{ .reply = ask.source_msg_id },
            .title = title,
            .description = &.{
                "[",
                issue.title.constSlice(),
                "](",
                issue.html_url.constSlice(),
                ")",
            },
            .color = if (is_pull_request) HexColor.blue else HexColor.green,
        });
    } else {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        if (self.last_reload != reload_counter) {
            try self.prepared_anal.reloadCached(&arena);
            self.last_reload = reload_counter;
        }
        if (try self.prepared_anal.analyse(&arena, ask_text)) |match| {
            _ = try self.sendDiscordMessage(.{
                .channel_id = ask.channel_id,
                .target_msg_id = .{ .reply = ask.source_msg_id },
                .title = ask_text,
                .description = &.{std.mem.trim(u8, match, " \t\r\n")},
                .color = .red,
            });
        }
    }
}

// This breaks out of the passed-in buffer and prepends/postpends with wrapper text.
// Thar be dragons 🐉
fn wrapString(buffer: []u8, wrapper: []const u8) []u8 {
    const start_ptr = buffer.ptr - wrapper.len;
    const frame = start_ptr[0 .. buffer.len + 2 * wrapper.len];
    std.mem.copy(u8, frame[0..], wrapper);
    std.mem.copy(u8, frame[buffer.len + wrapper.len ..], wrapper);
    return frame;
}

fn parseRun(self: WorkContext, ask: []const u8) ![]const u8 {
    _ = self;
    // we impliment a rudimentary tokenizer
    var b_num: u8 = 0;
    var start_idx: usize = 0;
    var end_idx: usize = 0;
    var state: enum { start, before_text_lang, text } = .start;
    for (ask) |c, i| {
        // skip run
        if (i < 4) continue;
        switch (state) {
            .start => switch (c) {
                '`' => {
                    b_num += 1;
                    if (b_num == 2) {
                        b_num = 0;
                        state = .before_text_lang;
                    }
                },
                ' ', '\t', '\n' => continue,
                else => return error.InvalidInput,
            },
            .before_text_lang => {
                switch (c) {
                    'a'...'z',
                    'A'...'Z',
                    '`',
                    => continue,
                    else => {
                        state = .text;
                        start_idx = i;
                    },
                }
            },
            .text => switch (c) {
                '`' => {
                    b_num += 1;
                    if (b_num == 2) {
                        end_idx = i - 1;
                        break;
                    }
                },
                else => continue,
            },
        }
    }
    if (start_idx == 0) return error.InvalidInput;
    if (end_idx == 0) return error.InvalidInput;
    return ask[start_idx..end_idx];
}

fn maybeGithubIssue(self: WorkContext, ask: []const u8) !?GithubIssue {
    if (std.fmt.parseInt(u32, ask, 10)) |_| {
        return try self.requestGithubIssue("ziglang/zig", ask);
    } else |_| {}

    const slash = std.mem.indexOfScalar(u8, ask, '/') orelse return null;
    const pound = std.mem.indexOfScalar(u8, ask, '#') orelse return null;

    if (slash > pound) return null;

    return try self.requestGithubIssue(ask[0..pound], ask[pound + 1 ..]);
}

const EmbedField = struct { name: []const u8, value: []const u8 };

pub fn sendDiscordMessage(self: WorkContext, args: struct {
    channel_id: zCord.Snowflake(.channel),
    target_msg_id: union(enum) {
        edit: zCord.Snowflake(.message),
        reply: zCord.Snowflake(.message),
    },
    title: []const u8,
    color: HexColor = HexColor.black,
    description: []const []const u8 = &.{},
    fields: []const EmbedField = &.{},
    image: ?[]const u8 = null,
}) !zCord.Snowflake(.message) {
    var path_buf: [0x100]u8 = undefined;

    const method: zCord.https.Request.Method = switch (args.target_msg_id) {
        .edit => .PATCH,
        .reply => .POST,
    };
    const path = switch (args.target_msg_id) {
        .edit => |msg_id| try std.fmt.bufPrint(&path_buf, "/api/v6/channels/{d}/messages/{d}", .{ args.channel_id, msg_id }),
        .reply => try std.fmt.bufPrint(&path_buf, "/api/v6/channels/{d}/messages", .{args.channel_id}),
    };

    // Zig has difficulty resolving these peer types
    const image: ?struct { url: []const u8 } = if (args.image) |url| .{ .url = url } else null;
    const message_reference: ?struct { message_id: zCord.Snowflake(.message) } = switch (args.target_msg_id) {
        .reply => |msg_id| .{ .message_id = msg_id },
        else => null,
    };

    const embed = .{
        .title = args.title,
        .color = @enumToInt(args.color),
        .description = format.concat(args.description),
        .fields = args.fields,
        .image = image,
    };

    var req = try self.zcord_client.sendRequest(self.allocator, method, path, .{
        .content = "",
        .tts = false,
        .embed = embed,
        .message_reference = message_reference,
    });
    defer req.deinit();

    const resp_code = req.response_code.?;
    if (resp_code.group() == .success) {
        try req.completeHeaders();

        var stream = zCord.json.stream(req.client.reader());

        const root = try stream.root();
        if (try root.objectMatchOne("id")) |match| {
            return try zCord.Snowflake(.message).consumeJsonElement(match.value);
        }
        return error.IdNotFound;
    } else switch (resp_code) {
        .client_too_many_requests => {
            try req.completeHeaders();

            var stream = zCord.json.stream(req.client.reader());
            const root = try stream.root();

            if (try root.objectMatchOne("retry_after")) |match| {
                const sec = try match.value.number(f64);
                // Don't bother trying for awhile
                std.time.sleep(@floatToInt(u64, sec * std.time.ns_per_s));
            }
            return error.TooManyRequests;
        },
        else => {
            std.debug.print("{} - {s}\n", .{ @enumToInt(resp_code), @tagName(resp_code) });
            return error.UnknownRequestError;
        },
    }
}

pub fn requestRun(self: WorkContext, src: [][]const u8, stdout_buf: []u8, stderr_buf: []u8) !RunResult {
    var req = try zCord.https.Request.init(.{
        .allocator = self.allocator,
        .host = "emkc.org",
        .method = .POST,
        .path = "/api/v1/piston/execute",
    });
    defer req.deinit();

    try req.client.writeHeaderValue("Content-Type", "application/json");

    const resp_code = try req.sendPrint("{}", .{
        format.json(.{
            .language = "zig",
            .source = format.concat(src),
            .stdin = "",
            .args = [0][]const u8{},
        }),
    });

    if (resp_code.group() != .success) {
        switch (resp_code) {
            .client_too_many_requests => return error.TooManyRequests,
            else => {
                std.debug.print("{} - {s}\n", .{ @enumToInt(resp_code), @tagName(resp_code) });
                return error.UnknownRequestError;
            },
        }
    }

    try req.completeHeaders();

    var stream = zCord.json.stream(req.client.reader());
    const root = try stream.root();

    var result = RunResult{
        .stdout = stdout_buf[0..0],
        .stderr = stderr_buf[0..0],
    };

    while (try root.objectMatch(enum { stdout, stderr })) |match| switch (match.key) {
        .stdout => {
            result.stdout = match.value.stringBuffer(stdout_buf) catch |err| switch (err) {
                error.StreamTooLong => stdout_buf,
                else => |e| return e,
            };
            _ = try match.value.finalizeToken();
        },
        .stderr => {
            result.stderr = match.value.stringBuffer(stderr_buf) catch |err| switch (err) {
                error.StreamTooLong => stderr_buf,
                else => |e| return e,
            };
            _ = try match.value.finalizeToken();
        },
    };
    return result;
}

const GithubIssue = struct { number: u32, title: std.BoundedArray(u8, 0x100), html_url: std.BoundedArray(u8, 0x100) };
const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
};
// from https://gist.github.com/thomasbnt/b6f455e2c7d743b796917fa3c205f812
const HexColor = enum(u24) {
    black = 0,
    aqua = 0x1ABC9C,
    green = 0x2ECC71,
    blue = 0x3498DB,
    red = 0xE74C3C,
    gold = 0xF1C40F,
    _,

    pub fn init(raw: u32) HexColor {
        return @intToEnum(HexColor, raw);
    }
};
pub fn requestGithubIssue(self: WorkContext, repo: []const u8, issue: []const u8) !GithubIssue {
    var path: [0x100]u8 = undefined;
    var req = try zCord.https.Request.init(.{
        .allocator = self.allocator,
        .host = "api.github.com",
        .method = .GET,
        .path = try std.fmt.bufPrint(&path, "/repos/{s}/issues/{s}", .{ repo, issue }),
    });
    defer req.deinit();

    try req.client.writeHeaderValue("Accept", "application/json");
    if (self.github_auth_token) |github_auth_token| {
        try req.client.writeHeaderFormat("Authorization", "token {s}", .{github_auth_token});
    }

    const resp_code = try req.sendEmptyBody();
    if (resp_code.group() != .success) {
        std.debug.print("{} - {s}\n", .{ @enumToInt(resp_code), @tagName(resp_code) });
        return error.UnknownRequestError;
    }

    try req.completeHeaders();

    var stream = zCord.json.stream(req.client.reader());
    const root = try stream.root();
    return try zCord.json.path.match(root, GithubIssue);
}
