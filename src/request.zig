const std = @import("std");
const hzzp = @import("hzzp");
const ssl = @import("zig-bearssl");

const bot_agent = "zigbot9001/0.0.1";

pub const SslTunnel = struct {
    allocator: *std.mem.Allocator,

    trust_anchor: *ssl.TrustAnchorCollection,
    x509: *ssl.x509.Minimal,
    client: ssl.Client,

    tcp_conn: std.fs.File,
    tcp_reader: std.fs.File.Reader,
    tcp_writer: std.fs.File.Writer,

    conn: Stream,

    pub const Stream = ssl.Stream(*std.fs.File.Reader, *std.fs.File.Writer);

    pub fn connect(self: *SslTunnel, args: struct {
        allocator: *std.mem.Allocator,
        host: [:0]const u8,
        port: u16 = 443,
    }) !void {
        self.client = ssl.Client.init(self.x509.getEngine());
        self.client.relocate();
        try self.client.reset(args.host, false);

        self.tcp_conn = try std.net.tcpConnectToHost(args.allocator, args.host, args.port);
        errdefer self.tcp_conn.close();

        self.tcp_reader = self.tcp_conn.reader();
        self.tcp_writer = self.tcp_conn.writer();

        self.conn = ssl.initStream(self.client.getEngine(), &self.tcp_reader, &self.tcp_writer);
    }

    pub fn init(allocator: *std.mem.Allocator, pem: []const u8) !*SslTunnel {
        const result = try allocator.create(SslTunnel);
        errdefer allocator.destroy(result);

        result.allocator = allocator;

        result.trust_anchor = try allocator.create(ssl.TrustAnchorCollection);
        result.trust_anchor.* = ssl.TrustAnchorCollection.init(allocator);
        errdefer {
            result.trust_anchor.deinit();
            allocator.destroy(result.trust_anchor);
        }
        try result.trust_anchor.appendFromPEM(pem);

        result.x509 = try allocator.create(ssl.x509.Minimal);
        result.x509.* = ssl.x509.Minimal.init(result.trust_anchor.*);
        errdefer allocator.destroy(result.x509);

        return result;
    }

    pub fn deinit(self: *SslTunnel) void {
        self.tcp_conn.close();
        self.trust_anchor.deinit();
        self.allocator.destroy(self.trust_anchor);
        self.allocator.destroy(self.x509);
        self.allocator.destroy(self);
    }
};

pub const Https = struct {
    allocator: *std.mem.Allocator,
    ssl_tunnel: *SslTunnel,
    buffer: []u8,
    client: HzzpClient,

    const HzzpClient = hzzp.base.Client.Client(SslTunnel.Stream.DstInStream, SslTunnel.Stream.DstOutStream);

    pub fn init(args: struct {
        allocator: *std.mem.Allocator,
        host: [:0]const u8,
        port: u16 = 443,
        method: []const u8,
        path: []const u8,
        ssl_tunnel: *SslTunnel,
    }) !Https {
        try args.ssl_tunnel.connect(.{
            .allocator = args.allocator,
            .host = args.host,
            .port = args.port,
        });

        const buffer = try args.allocator.alloc(u8, 0x1000);
        errdefer args.allocator.free(buffer);

        var client = hzzp.base.Client.create(buffer, args.ssl_tunnel.conn.inStream(), args.ssl_tunnel.conn.outStream());

        try client.writeHead(args.method, args.path);

        try client.writeHeaderValue("Host", args.host);
        try client.writeHeaderValue("User-Agent", bot_agent);

        return Https{
            .allocator = args.allocator,
            .ssl_tunnel = args.ssl_tunnel,
            .buffer = buffer,
            .client = client,
        };
    }

    pub fn deinit(self: *Https) void {
        self.allocator.free(self.buffer);
        self.* = undefined;
    }

    // TODO: fix this name
    pub fn printSend(self: *Https, comptime fmt: []const u8, args: anytype) !void {
        var buf: [0x10]u8 = undefined;
        try self.client.writeHeaderValue(
            "Content-Length",
            try std.fmt.bufPrint(&buf, "{}", .{std.fmt.count(fmt, args)}),
        );
        try self.client.writeHeadComplete();

        try self.client.writer.print(fmt, args);
        try self.ssl_tunnel.conn.flush();
    }

    pub fn expectSuccessStatus(self: *Https) !u16 {
        if (try self.client.readEvent()) |event| {
            if (event != .status) {
                return error.MissingStatus;
            }
            switch (event.status.code) {
                200...299 => return event.status.code,
                100...199 => return error.Internal,
                300...399 => return error.Redirect,
                400 => return error.InvalidRequest,
                401 => return error.Unauthorized,
                402 => return error.PaymentRequired,
                403 => return error.Forbidden,
                404 => return error.NotFound,
                405...499 => return error.ClientError,
                500...599 => return error.ServerError,
                else => unreachable,
            }
        } else {
            return error.NoResponse;
        }
    }

    pub fn completeHeaders(self: *Https) !void {
        while (try self.client.readEvent()) |event| {
            if (event == .head_complete) {
                return;
            }
        }
    }

    pub fn body(self: *Https) ChunkyReader(HzzpClient) {
        return .{ .client = self.client };
    }
};

pub fn ChunkyReader(comptime Chunker: type) type {
    return struct {
        const Self = @This();
        const ReadEventInfo = blk: {
            const ReturnType = @typeInfo(@TypeOf(Chunker.readEvent)).Fn.return_type.?;
            break :blk @typeInfo(ReturnType).ErrorUnion;
        };

        const Reader = std.io.Reader(*Self, ReadEventInfo.error_set, readFn);

        client: Chunker,
        complete: bool = false,
        event: ReadEventInfo.payload = null,
        loc: usize = undefined,

        fn readFn(self: *Self, buffer: []u8) ReadEventInfo.error_set!usize {
            if (self.complete) return 0;

            if (self.event) |event| {
                const remaining = event.chunk.data[self.loc..];
                if (buffer.len < remaining.len) {
                    std.mem.copy(u8, buffer, remaining[0..buffer.len]);
                    self.loc += buffer.len;
                    return buffer.len;
                } else {
                    std.mem.copy(u8, buffer, remaining);
                    if (event.chunk.final) {
                        self.complete = true;
                    }
                    self.event = null;
                    return remaining.len;
                }
            } else {
                const event = (try self.client.readEvent()) orelse {
                    self.complete = true;
                    return 0;
                };

                if (event != .chunk) {
                    self.complete = true;
                    return 0;
                }

                self.event = event;
                self.loc = 0;
                return self.readFn(buffer);
            }
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}
