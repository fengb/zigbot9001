const std = @import("std");
const hzzp = @import("hzzp");
const wz = @import("wz");
const ssl = @import("zig-bearssl");
const analBuddy = @import("analysis-buddy");

const format = @import("format.zig");
const request = @import("request.zig");
const util = @import("util.zig");

const agent = "zigbot9001/0.0.1";

pub usingnamespace if (std.builtin.mode != .Debug) struct {} else struct {
    pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
        std.debug.print("PANIC -- {}\n", .{msg});

        const err = std.os.execveZ(
            std.os.argv[0],
            @ptrCast([*:null]?[*:0]u8, std.os.argv.ptr),
            @ptrCast([*:null]?[*:0]u8, std.os.environ.ptr),
        );

        std.debug.print("{}\n", .{@errorName(err)});
        std.os.exit(42);
    }
};

fn Buffer(comptime max_len: usize) type {
    return struct {
        data: [max_len]u8 = undefined,
        len: usize = 0,

        fn slice(self: @This()) []const u8 {
            return self.data[0..self.len];
        }
    };
}

const Context = struct {
    allocator: *std.mem.Allocator,
    discord_auth_token: []const u8,
    github_auth_token: ?[]const u8,
    prepared_anal: analBuddy.PrepareResult,
    discord_ssl_tunnel: *request.SslTunnel,
    discord_ssl_tunnel_gg: *request.SslTunnel,
    github_ssl_tunnel: *request.SslTunnel,

    start_time: i64,
    connect_time: i64,

    ask_mailbox: util.Mailbox(AskData),
    ask_thread: *std.Thread,

    const AskData = struct { ask: Buffer(0x100), channel_id: u64 };

    pub fn init(args: struct {
        allocator: *std.mem.Allocator,
        discord_auth: []const u8,
        github_auth: ?[]const u8,
        ziglib: []const u8,
        discord_ssl_tunnel: *request.SslTunnel,
        discord_ssl_tunnel_gg: *request.SslTunnel,
        github_ssl_tunnel: *request.SslTunnel,
    }) !*Context {
        const result = try args.allocator.create(Context);
        errdefer args.allocator.destroy(result);

        result.allocator = args.allocator;
        result.discord_auth_token = args.discord_auth;
        result.github_auth_token = args.github_auth;
        result.prepared_anal = try analBuddy.prepare(args.allocator, args.ziglib);
        errdefer analBuddy.dispose(&result.prepared_anal);

        result.start_time = std.time.milliTimestamp();

        result.ask_mailbox = util.Mailbox(AskData).init();
        result.discord_ssl_tunnel = args.discord_ssl_tunnel;
        result.discord_ssl_tunnel_gg = args.discord_ssl_tunnel_gg;
        result.github_ssl_tunnel = args.github_ssl_tunnel;
        result.ask_thread = try std.Thread.spawn(result, askHandler);

        return result;
    }

    pub fn askHandler(self: *Context) void {
        while (true) {
            var mailbox = self.ask_mailbox.get();
            self.askOne(mailbox.channel_id, mailbox.ask.slice()) catch |err| {
                std.debug.print("{}\n", .{err});
            };
        }
    }

    pub fn askOne(self: *Context, channel_id: u64, ask: []const u8) !void {
        const swh = util.Swhash(16);
        switch (swh.match(ask)) {
            swh.case("ping") => return try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .title = "pong",
                .body =
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
                            }),
            swh.case("uptime") => {
                var buf: [0x1000]u8 = undefined;
                const current = std.time.milliTimestamp();
                return try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = "",
                    .body = std.fmt.bufPrint(
                        &buf,
                        \\```
                        \\Uptime:    {}
                        \\Connected: {}
                        \\```
                    ,
                        .{ format.time(@intCast(u64, current - self.start_time)), format.time(@intCast(u64, current - self.connect_time)) },
                    ) catch unreachable,
                });
            },
            swh.case("zen") => return try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .title = "For Great Justice",
                .body =
                    \\```
                    \\∗ Communicate intent precisely.
                    \\∗ Edge cases matter.
                    \\∗ Favor reading code over writing code.
                    \\∗ Only one obvious way to do things.
                    \\∗ Runtime crashes are better than bugs.
                    \\∗ Compile errors are better than runtime crashes.
                    \\∗ Incremental improvements.
                    \\∗ Avoid local maximums.
                    \\∗ Reduce the amount one must remember.
                    \\∗ Minimize energy spent on coding style.
                    \\∗ Resource deallocation must succeed.
                    \\∗ Together we serve end users.
                    \\```
                            }),
            swh.case("zenlang"),
            swh.case("v"),
            swh.case("vlang"),
            => return try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .title = "bruh",
                .body = "",
            }),
            swh.case("u0") => return try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .title = "Zig's billion dollar mistake™",
                .body = "https://github.com/ziglang/zig/issues/1530#issuecomment-422113755",
            }),
            swh.case("5076") => return try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .color = .green,
                .title = "Issue #5076 — syntax: drop the `const` keyword in global scopes",
                .body =
                    \\~~https://github.com/ziglang/zig/issues/5076~~
                    \\https://www.youtube.com/watch?v=880uR25pP5U
                            }),
            else => {},
        }

        if (std.fmt.parseInt(u32, ask, 10)) |issue| {
            const gh_issue = try self.requestGithubIssue(issue);

            const is_pull_request = std.mem.indexOf(u8, gh_issue.url.slice(), "/pull/") != null;
            const label = if (is_pull_request) "Pull" else "Issue";

            var buf: [0x1000]u8 = undefined;
            const title = try std.fmt.bufPrint(&buf, "{} #{} — {}", .{ label, gh_issue.number, gh_issue.title.slice() });
            try self.sendDiscordMessage(.{
                .channel_id = channel_id,
                .title = title,
                .body = gh_issue.url.slice(),
                .color = if (is_pull_request) HexColor.blue else HexColor.green,
            });
        } else |_| {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            if (try analBuddy.analyse(&arena, &self.prepared_anal, ask)) |match| {
                try self.sendDiscordMessage(.{
                    .channel_id = channel_id,
                    .title = ask,
                    .body = std.mem.trim(u8, match, " \t\r\n"),
                    .color = .red,
                });
            } else {}
        }
    }

    pub fn sendDiscordMessage(self: Context, args: struct {
        channel_id: u64,
        title: []const u8,
        body: []const u8,
        color: HexColor = HexColor.black,
    }) !void {
        var path: [0x100]u8 = undefined;
        var req = try request.Https.init(.{
            .allocator = self.allocator,
            .ssl_tunnel = self.discord_ssl_tunnel,
            .host = "discord.com",
            .method = "POST",
            .path = try std.fmt.bufPrint(&path, "/api/v6/channels/{}/messages", .{args.channel_id}),
        });
        defer req.deinit();

        try req.client.writeHeaderValue("Accept", "application/json");
        try req.client.writeHeaderValue("Content-Type", "application/json");
        try req.client.writeHeaderValue("Authorization", self.discord_auth_token);

        try req.printSend(
            \\{{
            \\  "content": "",
            \\  "tts": false,
            \\  "embed": {{
            \\    "title": "{0}",
            \\    "description": "{1}",
            \\    "color": {2}
            \\  }}
            \\}}
        ,
            .{ format.jsonString(args.title), format.jsonString(args.body), @enumToInt(args.color) },
        );

        _ = try req.expectSuccessStatus();
    }

    const GithubIssue = struct { number: u32, title: Buffer(0x100), url: Buffer(0x100) };
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
    pub fn requestGithubIssue(self: Context, issue: u32) !GithubIssue {
        var path: [0x100]u8 = undefined;
        var req = try request.Https.init(.{
            .allocator = self.allocator,
            .ssl_tunnel = self.github_ssl_tunnel,
            .host = "api.github.com",
            .method = "GET",
            .path = try std.fmt.bufPrint(&path, "/repos/ziglang/zig/issues/{}", .{issue}),
        });
        defer req.deinit();

        try req.client.writeHeaderValue("Accept", "application/json");
        if (self.github_auth_token) |github_auth_token| {
            try req.client.writeHeaderValue("Authorization", github_auth_token);
        }
        try req.client.writeHeadComplete();
        try req.ssl_tunnel.conn.flush();

        _ = try req.expectSuccessStatus();
        try req.completeHeaders();
        var body = req.body();
        var stream = util.streamJson(body.reader());
        const root = try stream.root();

        var result = GithubIssue{ .number = issue, .title = .{}, .url = .{} };
        while (try root.objectMatchAny(&[_][]const u8{ "title", "html_url" })) |match| {
            const swh = util.Swhash(16);
            switch (swh.match(match.key)) {
                swh.case("html_url") => {
                    const slice = try match.value.stringBuffer(&result.url.data);
                    result.url.len = slice.len;
                },
                swh.case("title") => {
                    const slice = try match.value.stringBuffer(&result.title.data);
                    result.title.len = slice.len;
                },
                else => unreachable,
            }

            if (result.title.len > 0 and result.url.len > 0) {
                return result;
            }
        }

        return error.FieldNotFound;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var auth_buf: [0x100]u8 = undefined;
    const discord_auth = try std.fmt.bufPrint(&auth_buf, "Bot {}", .{std.os.getenv("DISCORD_AUTH") orelse return error.AuthNotFound});
    var github_auth_buf: [0x100]u8 = undefined;
    const github_auth = if (std.os.getenv("GITHUB_AUTH")) |github_auth|
        try std.fmt.bufPrint(&github_auth_buf, "token {}", .{github_auth})
    else
        null;

    const discord_ssl_tunnel = try request.SslTunnel.init(
        &gpa.allocator,
        @embedFile("../discord-com-chain.pem"),
    );
    errdefer discord_ssl_tunnel.deinit();
    const discord_ssl_tunnel_gg = try request.SslTunnel.init(
        &gpa.allocator,
        @embedFile("../discord-gg-chain.pem"),
    );
    errdefer discord_ssl_tunnel_gg.deinit();
    const github_ssl_tunnel = try request.SslTunnel.init(
        &gpa.allocator,
        @embedFile("../github-com-chain.pem"),
    );
    errdefer github_ssl_tunnel.deinit();

    const context = try Context.init(.{
        .allocator = &gpa.allocator,
        .discord_auth = discord_auth,
        .github_auth = github_auth,
        .ziglib = std.os.getenv("ZIGLIB") orelse return error.ZiglibNotFound,
        .discord_ssl_tunnel = discord_ssl_tunnel,
        .discord_ssl_tunnel_gg = discord_ssl_tunnel_gg,
        .github_ssl_tunnel = github_ssl_tunnel,
    });

    while (true) {
        var discord_ws = try DiscordWs.init(context);
        defer discord_ws.deinit();

        context.connect_time = std.time.milliTimestamp();

        discord_ws.run(context, struct {
            fn handleDispatch(ctx: *Context, name: []const u8, data: anytype) !void {
                if (!std.mem.eql(u8, name, "MESSAGE_CREATE")) return;

                var ask: Buffer(0x100) = .{};
                var channel_id: ?u64 = null;

                while (try data.objectMatchAny(&[_][]const u8{ "content", "channel_id" })) |match| {
                    const swh = util.Swhash(16);
                    switch (swh.match(match.key)) {
                        swh.case("content") => {
                            var reader = try match.value.stringReader();
                            ask = try findAsk(reader);

                            // Throw away the rest of this reader
                            // TODO: push this into finalizeToken (?)
                            var buf: [0x100]u8 = undefined;
                            while ((try reader.read(&buf)) != 0) {}
                        },
                        swh.case("channel_id") => {
                            var buf: [0x100]u8 = undefined;
                            const channel_string = try match.value.stringBuffer(&buf);
                            channel_id = try std.fmt.parseInt(u64, channel_string, 10);
                        },
                        else => unreachable,
                    }
                }

                if (ask.len > 0 and channel_id != null) {
                    std.debug.print(">> %%{}\n", .{ask.slice()});
                    ctx.ask_mailbox.putOverwrite(.{ .channel_id = channel_id.?, .ask = ask });
                }
            }

            fn findAsk(reader: anytype) !Buffer(0x100) {
                const State = enum {
                    no_match,
                    percent,
                    ready,
                };
                var state = State.no_match;
                var buffer: Buffer(0x100) = .{};

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
                                ' ', ',', '\n', '\t' => return buffer,
                                else => {
                                    buffer.data[buffer.len] = c;
                                    buffer.len += 1;
                                },
                            }
                        },
                    }
                } else |err| switch (err) {
                    error.EndOfStream => return buffer,
                    else => |e| return e,
                }
            }
        }) catch |err| switch (err) {
            // TODO: investigate if IO localized enough. And possibly convert to ConnectionReset
            error.ConnectionReset, error.IO => continue,
            else => @panic(@errorName(err)),
        };

        std.debug.print("Exited: {}\n", .{discord_ws.client});
    }
}

const DiscordWs = struct {
    allocator: *std.mem.Allocator,

    is_dying: bool,
    ssl_tunnel: *request.SslTunnel,

    client: wz.base.Client.Client(request.SslTunnel.Stream.DstInStream, request.SslTunnel.Stream.DstOutStream),
    client_buffer: []u8,
    write_mutex: std.Mutex,

    heartbeat_interval: usize,
    heartbeat_seq: ?usize,
    heartbeat_ack: bool,
    heartbeat_thread: *std.Thread,

    const Opcode = enum {
        /// An event was dispatched.
        dispatch = 0,
        /// Fired periodically by the client to keep the connection alive.
        heartbeat = 1,
        /// Starts a new session during the initial handshake.
        identify = 2,
        /// Update the client's presence.
        presence_update = 3,
        /// Used to join/leave or move between voice channels.
        voice_state_update = 4,
        /// Resume a previous session that was disconnected.
        @"resume" = 6,
        /// You should attempt to reconnect and resume immediately.
        reconnect = 7,
        /// Request information about offline guild members in a large guild.
        request_guild_members = 8,
        /// The session has been invalidated. You should reconnect and identify/resume accordingly.
        invalid_session = 9,
        /// Sent immediately after connecting, contains the heartbeat_interval to use.
        hello = 10,
        /// Sent in response to receiving a heartbeat to acknowledge that it has been received.
        heartbeat_ack = 11,
    };

    pub fn init(context: *Context) !*DiscordWs {
        const allocator = context.allocator;
        const result = try allocator.create(DiscordWs);
        errdefer allocator.destroy(result);
        result.allocator = allocator;

        result.write_mutex = .{};

        result.ssl_tunnel = context.discord_ssl_tunnel_gg;

        try result.ssl_tunnel.connect(.{
            .allocator = allocator,
            .host = "gateway.discord.gg",
        });

        result.client_buffer = try allocator.alloc(u8, 0x1000);
        errdefer allocator.free(result.client_buffer);

        result.client = wz.base.Client.create(
            result.client_buffer,
            result.ssl_tunnel.conn.inStream(),
            result.ssl_tunnel.conn.outStream(),
        );

        // Handshake
        try result.client.sendHandshakeHead("/?v=6&encoding=json");
        try result.client.sendHandshakeHeaderValue("Host", "gateway.discord.gg");
        try result.client.sendHandshakeHeadComplete();
        try result.ssl_tunnel.conn.flush();
        try result.client.waitForHandshake();

        if (try result.client.readEvent()) |event| {
            std.debug.assert(event == .header);
        }

        result.is_dying = false;
        result.heartbeat_interval = 0;
        if (try result.client.readEvent()) |event| {
            std.debug.assert(event == .chunk);

            var fba = std.io.fixedBufferStream(event.chunk.data);
            var stream = util.streamJson(fba.reader());

            const root = try stream.root();
            while (try root.objectMatchAny(&[_][]const u8{ "op", "d" })) |match| {
                const swh = util.Swhash(2);
                switch (swh.match(match.key)) {
                    swh.case("op") => {
                        const op = try std.meta.intToEnum(Opcode, try match.value.number(u8));
                        if (op != .hello) {
                            return error.MalformedHelloResponse;
                        }
                    },
                    swh.case("d") => {
                        while (try match.value.objectMatch("heartbeat_interval")) |hbi| {
                            result.heartbeat_interval = try hbi.value.number(u32);
                        }
                    },
                    else => unreachable,
                }
            }
        }

        if (result.heartbeat_interval == 0) {
            return error.MalformedHelloResponse;
        }

        // Identify
        try result.printMessage(
            \\ {{
            \\   "op": 2,
            \\   "d": {{
            \\     "compress": "false",
            \\     "token": "{0}",
            \\     "properties": {{
            \\       "$os": "{1}",
            \\       "$browser": "{2}",
            \\       "$device": "{2}"
            \\     }}
            \\   }}
            \\ }}
        ,
            .{
                format.jsonString(context.discord_auth_token),
                @tagName(std.Target.current.os.tag),
                agent,
            },
        );

        result.heartbeat_seq = null;
        result.heartbeat_ack = true;
        result.heartbeat_thread = try std.Thread.spawn(result, heartbeatHandler);

        return result;
    }

    pub fn deinit(self: *DiscordWs) void {
        if (!self.is_dying) {
            self.is_dying = true;
        }

        self.heartbeat_thread.wait();
        self.allocator.destroy(self);
    }

    pub fn run(self: *DiscordWs, ctx: anytype, handler: anytype) !void {
        while (try self.client.readEvent()) |event| {
            // Skip over any remaining chunks. The processor didn't take care of it.
            if (event != .header) continue;

            switch (event.header.opcode) {
                // Text Frame
                1 => {
                    self.processChunks(ctx, handler) catch |err| {
                        std.debug.print("Process chunks failed: {}\n", .{err});
                    };
                },
                // Ping, Pong
                9, 10 => {},
                8 => return error.ConnectionReset,
                2 => return error.WtfBinary,
                else => return error.WtfWtf,
            }
        }
    }
    pub fn processChunks(self: *DiscordWs, ctx: anytype, handler: anytype) !void {
        const event = (try self.client.readEvent()) orelse return error.NoBody;
        std.debug.assert(event == .chunk);

        var name_buf: [32]u8 = undefined;
        var name: ?[]u8 = null;
        var op: ?Opcode = null;

        var fba = std.io.fixedBufferStream(event.chunk.data);
        var stream = util.streamJson(fba.reader());
        const root = try stream.root();

        while (try root.objectMatchAny(&[_][]const u8{ "t", "s", "op", "d" })) |match| {
            const swh = util.Swhash(2);
            switch (swh.match(match.key)) {
                swh.case("t") => {
                    name = try match.value.optionalStringBuffer(&name_buf);
                },
                swh.case("s") => {
                    if (try match.value.optionalNumber(u32)) |seq| {
                        self.heartbeat_seq = seq;
                    }
                },
                swh.case("op") => {
                    op = try std.meta.intToEnum(Opcode, try match.value.number(u8));
                },
                swh.case("d") => {
                    switch (op orelse return error.DataBeforeOp) {
                        .dispatch => {
                            std.debug.print("<< {} -- {}\n", .{ self.heartbeat_seq, name });
                            try handler.handleDispatch(
                                ctx,
                                name orelse return error.DispatchWithoutName,
                                match.value,
                            );
                        },
                        .heartbeat_ack => {
                            std.debug.print("<< ♥\n", .{});
                            self.heartbeat_ack = true;
                            _ = try match.value.finalizeToken();
                        },
                        else => {
                            _ = try match.value.finalizeToken();
                        },
                    }
                },
                else => unreachable,
            }
        }
    }

    pub fn printMessage(self: *DiscordWs, comptime fmt: []const u8, args: anytype) !void {
        var buf: [0x1000]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, fmt, args);

        const held = self.write_mutex.acquire();
        defer held.release();

        try self.client.writeMessageHeader(.{ .length = msg.len, .opcode = 1 });

        var masked = std.mem.zeroes([0x1000]u8);
        self.client.maskPayload(msg, &masked);
        try self.client.writeMessagePayload(masked[0..msg.len]);

        try self.ssl_tunnel.conn.flush();
    }

    fn heartbeatHandler(self: *DiscordWs) void {
        while (true) {
            const start = std.time.milliTimestamp();
            // Buffer to fire early than late
            while (std.time.milliTimestamp() - start < self.heartbeat_interval - 1000) {
                std.time.sleep(std.time.ns_per_s);
                if (self.is_dying) {
                    return;
                }
            }

            if (!self.heartbeat_ack) {
                self.is_dying = true;
                return;
            }

            var retries: usize = 3;
            while (self.printMessage(
                \\ {{
                \\   "op": 1,
                \\   "d": {}
                \\ }}
            , .{self.heartbeat_seq})) |_| {
                std.debug.print(">> ♡\n", .{});
                self.heartbeat_ack = false;
                break;
            } else |err| {
                retries -= 1;
                if (retries == 0) {
                    // TODO: handle this better
                    @panic(@errorName(err));
                }

                std.os.nanosleep(1, 0);
            }
        }
    }
};

test "" {
    _ = request;
    _ = util;
}
