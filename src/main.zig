const std = @import("std");
const zCord = @import("zCord");
const analBuddy = @import("analysis-buddy");

const format = @import("format.zig");
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

fn Buffer(comptime max_len: usize) type {
    return struct {
        data: [max_len]u8 = undefined,
        len: usize = 0,

        fn initFrom(data: []const u8) @This() {
            var result: @This() = undefined;
            std.mem.copy(u8, &result.data, data);
            result.len = data.len;
            return result;
        }

        fn slice(self: @This()) []const u8 {
            return self.data[0..self.len];
        }

        fn append(self: *@This(), char: u8) !void {
            if (self.len >= max_len) {
                return error.NoSpaceLeft;
            }
            self.data[self.len] = char;
            self.len += 1;
        }

        fn last(self: @This()) ?u8 {
            if (self.len > 0) {
                return self.data[self.len - 1];
            } else {
                return null;
            }
        }

        fn pop(self: *@This()) !u8 {
            return self.last() orelse error.Empty;
        }
    };
}

const Context = struct {
    allocator: *std.mem.Allocator,
    auth_token: []const u8,
    github_auth_token: ?[]const u8,
    prng: std.rand.DefaultPrng,
    prepared_anal: analBuddy.PrepareResult,

    timer: std.time.Timer,

    ask_mailbox: util.Mailbox(AskData),
    ask_thread: *std.Thread,

    // TODO move this to instance variable somehow?
    var awaiting_enema = false;

    const AskData = struct { ask: Buffer(0x1000), channel_id: zCord.Snowflake(.channel) };

    pub fn init(allocator: *std.mem.Allocator, auth_token: []const u8, ziglib: []const u8, github_auth_token: ?[]const u8) !*Context {
        const result = try allocator.create(Context);
        errdefer allocator.destroy(result);

        result.allocator = allocator;
        result.auth_token = auth_token;
        result.github_auth_token = github_auth_token;
        result.prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp()));
        result.prepared_anal = try analBuddy.prepare(allocator, ziglib);
        errdefer analBuddy.dispose(&result.prepared_anal);

        result.timer = try std.time.Timer.start();

        result.ask_mailbox = .{};
        result.ask_thread = try std.Thread.spawn(askHandler, result);

        std.os.sigaction(
            std.os.SIGWINCH,
            &std.os.Sigaction{
                .handler = .{
                    .handler = winchHandler,
                },
                .mask = std.os.empty_sigset,
                .flags = 0,
            },
            null,
        );

        return result;
    }

    fn winchHandler(signum: c_int) callconv(.C) void {
        awaiting_enema = true;
    }

    pub fn askHandler(self: *Context) void {
        while (true) {
            const mailbox = self.ask_mailbox.get();
            self.askOne(mailbox.channel_id, mailbox.ask.slice()) catch |err| {
                std.debug.print("{s}\n", .{err});
            };
        }
    }

    pub fn askOne(self: *Context, channel_id: zCord.Snowflake(.channel), ask: []const u8) !void {
        const swh = util.Swhash(16);
        switch (swh.match(ask)) {
            swh.case("ping") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "pong",
                    .description = &.{
                        \\```
                        \\          ,;;;!!!!!;;.
                        \\        :!!!!!!!!!!!!!!;
                        \\      :!!!!!!!!!!!!!!!!!;
                        \\     ;!!!!!!!!!!!!!!!!!!!;
                        \\    ;!!!!!!!!!!!!!!!!!!!!!
                        \\    ;!!!!!!!!!!!!!!!!!!!!'
                        \\    ;!!!!!!!!!!!!!!!!!!!'
                        \\     :!!!!!!!!!!!!!!!!'
                        \\      ,!!!!!!!!!!!!!''
                        \\   ,;!!!''''''''''
                        \\ .!!!!'
                        \\!!!!`
                        \\```
                    },
                });
                return;
            },
            swh.case("status") => {
                const rusage = std.os.getrusage(std.os.RUSAGE_SELF);
                const cpu_sec = (rusage.utime.tv_sec + rusage.stime.tv_sec) * 1000;
                const cpu_us = @divFloor(rusage.utime.tv_usec + rusage.stime.tv_usec, 1000);

                var buf: [0x1000]u8 = undefined;
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
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
                    .channel_id = channel_id,
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
                    .channel_id = channel_id,
                    .title = "bruh",
                });
                return;
            },
            swh.case("u0") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "Zig's billion dollar mistake™",
                    .description = &.{"https://github.com/ziglang/zig/issues/1530#issuecomment-422113755"},
                });
                return;
            },
            swh.case("tater") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "",
                    .image = "https://memegenerator.net/img/instances/41913604.jpg",
                });
                return;
            },
            swh.case("5076"), swh.case("ziglang/zig#5076") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
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
                    .channel_id = channel_id,
                    .title = "git submodules are the devil — _andrewrk_",
                    .description = &.{"https://github.com/ziglang/zig-bootstrap/issues/17#issuecomment-609980730"},
                });
                return;
            },
            swh.case("2.718"), swh.case("2.71828") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "",
                    .image = "https://camo.githubusercontent.com/7f0d955df2205a170bf1582105c319ec6b00ec5c/68747470733a2f2f692e696d67666c69702e636f6d2f34646d7978702e6a7067",
                });
                return;
            },
            swh.case("bruh") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "",
                    .image = "https://user-images.githubusercontent.com/106511/86198112-6718ba00-bb46-11ea-92fd-d006b462c5b1.jpg",
                });
                return;
            },
            swh.case("dab") => {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "I promised I would dab and say “bruh” — _andrewrk_",
                    .description = &.{"https://vimeo.com/492676992"},
                    .image = "https://i.vimeocdn.com/video/1018725604.jpg?mw=700&mh=1243&q=70",
                });
                return;
            },
            else => {},
        }

        if (std.mem.startsWith(u8, ask, "run")) {
            const run = self.parseRun(ask) catch |e| switch (e) {
                error.InvalidInput => {
                    _ = try self.sendDiscordMessage(.{
                        .channel_id = channel_id,
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
                .channel_id = channel_id,
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
                    .channel_id = channel_id,
                    .edit_msg_id = msg_id,
                    .title = "Run error",
                    .description = &.{output},
                });
                return e;
            };

            var description: []const []const u8 = &.{};
            const all_fields = [_]EmbedField{
                .{ .name = "stdout", .value = wrapString(ran.stdout, "```") },
                .{ .name = "stderr", .value = wrapString(ran.stderr, "```") },
            };
            var fields: []const EmbedField = &.{};
            switch (b(.{ ran.stdout.len > 0, ran.stderr.len > 0 })) {
                b(.{ false, false }) => description = &.{"***No Output***"},
                b(.{ true, false }) => fields = all_fields[0..1],
                b(.{ false, true }) => fields = all_fields[1..],
                b(.{ true, true }) => fields = all_fields[0..],
            }

            _ = try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .edit_msg_id = msg_id,
                .title = "Run Results",
                .description = description,
                .fields = fields,
            });
            return;
        }

        if (try self.maybeGithubIssue(ask)) |issue| {
            const is_pull_request = std.mem.indexOf(u8, issue.url.slice(), "/pull/") != null;
            const label = if (is_pull_request) "pull" else "issue";

            var title_buf: [0x1000]u8 = undefined;
            const title = try std.fmt.bufPrint(&title_buf, "{s} — {s} #{d}", .{
                issue.repo.slice(),
                label,
                issue.number,
            });
            _ = try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .title = title,
                .description = &.{
                    "[",
                    issue.title.slice(),
                    "](",
                    issue.url.slice(),
                    ")",
                },
                .color = if (is_pull_request) HexColor.blue else HexColor.green,
            });
        } else {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            if (awaiting_enema) {
                try analBuddy.reloadCached(&arena, self.prepared_anal.store.allocator, &self.prepared_anal);
                awaiting_enema = false;
            }
            if (try analBuddy.analyse(&arena, &self.prepared_anal, ask)) |match| {
                _ = try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = ask,
                    .description = &.{std.mem.trim(u8, match, " \t\r\n")},
                    .color = .red,
                });
            } else {}
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

    fn parseRun(self: Context, ask: []const u8) ![]const u8 {
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

    fn maybeGithubIssue(self: Context, ask: []const u8) !?GithubIssue {
        if (std.fmt.parseInt(u32, ask, 10)) |issue| {
            return try self.requestGithubIssue("ziglang/zig", ask);
        } else |_| {}

        const slash = std.mem.indexOfScalar(u8, ask, '/') orelse return null;
        const pound = std.mem.indexOfScalar(u8, ask, '#') orelse return null;

        if (slash > pound) return null;

        return try self.requestGithubIssue(ask[0..pound], ask[pound + 1 ..]);
    }

    const EmbedField = struct { name: []const u8, value: []const u8 };

    pub fn sendDiscordMessage(self: Context, args: struct {
        channel_id: zCord.Snowflake(.channel),
        edit_msg_id: ?zCord.Snowflake(.message) = null,
        title: []const u8,
        color: HexColor = HexColor.black,
        description: []const []const u8 = &.{},
        fields: []const EmbedField = &.{},
        image: ?[]const u8 = null,
    }) !zCord.Snowflake(.message) {
        var path_buf: [0x100]u8 = undefined;

        const path = if (args.edit_msg_id) |msg_id|
            try std.fmt.bufPrint(&path_buf, "/api/v6/channels/{d}/messages/{d}", .{ args.channel_id, msg_id })
        else
            try std.fmt.bufPrint(&path_buf, "/api/v6/channels/{d}/messages", .{args.channel_id});

        var req = try zCord.https.Request.init(.{
            .allocator = self.allocator,
            .host = "discord.com",
            .method = if (args.edit_msg_id) |_| .PATCH else .POST,
            .path = path,
        });
        defer req.deinit();

        try req.client.writeHeaderValue("Accept", "application/json");
        try req.client.writeHeaderValue("Content-Type", "application/json");
        try req.client.writeHeaderValue("Authorization", self.auth_token);

        // Zig has difficulty resolving these peer types
        const image: ?struct { url: []const u8 } = if (args.image) |url| .{ .url = url } else null;

        const embed = .{
            .title = args.title,
            .color = @enumToInt(args.color),
            .description = format.concat(args.description),
            .fields = args.fields,
            .image = image,
        };
        const resp_code = try req.sendPrint("{}", .{
            format.json(.{
                .content = "",
                .tts = false,
                .embed = embed,
            }),
        });

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
                return error.UnknownError;
            },
        }
    }

    pub fn requestRun(self: Context, src: [][]const u8, stdout_buf: []u8, stderr_buf: []u8) !RunResult {
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
                    return error.UnknownError;
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

        while (try root.objectMatch(enum { stdout, stderr })) |match| switch (match) {
            .stdout => |e_stdout| {
                result.stdout = e_stdout.stringBuffer(stdout_buf) catch |err| switch (err) {
                    error.StreamTooLong => stdout_buf,
                    else => |e| return e,
                };
                _ = try e_stdout.finalizeToken();
            },
            .stderr => |e_stderr| {
                result.stderr = e_stderr.stringBuffer(stderr_buf) catch |err| switch (err) {
                    error.StreamTooLong => stderr_buf,
                    else => |e| return e,
                };
                _ = try e_stderr.finalizeToken();
            },
        };
        return result;
    }

    const GithubIssue = struct { repo: Buffer(0x100), number: u32, title: Buffer(0x100), url: Buffer(0x100) };
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
    pub fn requestGithubIssue(self: Context, repo: []const u8, issue: []const u8) !GithubIssue {
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
            return error.UnknownError;
        }

        try req.completeHeaders();
        var stream = zCord.json.stream(req.client.reader());
        const root = try stream.root();

        var result = GithubIssue{ .repo = Buffer(0x100).initFrom(repo), .number = 0, .title = .{}, .url = .{} };
        while (try root.objectMatch(enum { number, title, html_url })) |match| switch (match) {
            .number => |e_number| {
                result.number = try e_number.number(u32);
            },
            .html_url => |e_html_url| {
                const slice = try e_html_url.stringBuffer(&result.url.data);
                result.url.len = slice.len;
            },
            .title => |e_title| {
                const slice = try e_title.stringBuffer(&result.title.data);
                result.title.len = slice.len;
            },
        };

        if (result.number > 0 and result.title.len > 0 and result.url.len > 0) {
            return result;
        }

        return error.FieldNotFound;
    }
};

pub fn main() !void {
    std.os.sigaction(
        std.os.SIGUSR1,
        &std.os.Sigaction{
            .handler = .{
                .handler = struct {
                    fn handler(signum: c_int) callconv(.C) void {
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
    const context = try Context.init(
        &gpa.allocator,
        try std.fmt.bufPrint(&auth_buf, "Bot {s}", .{std.os.getenv("DISCORD_AUTH") orelse return error.AuthNotFound}),
        std.os.getenv("ZIGLIB") orelse return error.ZiglibNotFound,
        std.os.getenv("GITHUB_AUTH"),
    );

    const cli = try zCord.Client.create(.{
        .allocator = context.allocator,
        .auth_token = context.auth_token,
        .context = context,
        .intents = .{ .guild_messages = true },
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
    defer cli.destroy();

    cli.ws(struct {
        pub fn handleDispatch(client: *zCord.Client, name: []const u8, data: anytype) !void {
            if (!std.mem.eql(u8, name, "MESSAGE_CREATE")) return;

            var ask: Buffer(0x1000) = .{};
            var channel_id: ?zCord.Snowflake(.channel) = null;

            while (try data.objectMatch(enum { content, channel_id })) |match| switch (match) {
                .content => |e_content| {
                    ask = try findAsk(try e_content.stringReader());
                    _ = try e_content.finalizeToken();
                },
                .channel_id => |e_channel_id| {
                    channel_id = try zCord.Snowflake(.channel).consumeJsonElement(e_channel_id);
                    _ = try e_channel_id.finalizeToken();
                },
            };

            if (ask.len > 0 and channel_id != null) {
                std.debug.print(">> %%{s}\n", .{ask.slice()});
                client.ctx(Context).ask_mailbox.putOverwrite(.{ .channel_id = channel_id.?, .ask = ask });
            }
        }

        fn findAsk(reader: anytype) !Buffer(0x1000) {
            const State = enum {
                no_match,
                percent,
                ready,
                endless,
            };
            var state = State.no_match;
            var buffer: Buffer(0x1000) = .{};

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
                                if (std.mem.eql(u8, buffer.slice(), "run")) {
                                    state = .endless;
                                    try buffer.append(c);
                                } else {
                                    break;
                                }
                            },
                            else => try buffer.append(c),
                        }
                    },
                    .endless => try buffer.append(c),
                }
            } else |err| switch (err) {
                error.EndOfStream => {},
                else => |e| return e,
            }

            // Strip trailing period
            if (buffer.last() == @as(u8, '.')) {
                _ = buffer.pop() catch unreachable;
            }
            return buffer;
        }
    }) catch |err| switch (err) {
        error.AuthenticationFailed => |e| return e,
        else => @panic(@errorName(err)),
    };
}
