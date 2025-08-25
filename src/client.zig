const std = @import("std");

const ConnectionError = error{ConnectionRefused};

pub const Client = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,

    var connection: ?std.net.Stream = null;

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) *const Client {
        return &Client{
            .allocator = allocator,
            .host = host,
            .port = port,
        };
    }

    pub fn connect(self: *const Client) !void {
        const stdout = std.io.getStdOut().writer();

        connection = std.net.tcpConnectToHost(self.allocator, self.host, self.port) catch {
            return ConnectionError.ConnectionRefused;
        };

        const init_request = try self.buildRequest(0, "initialize", .{
            .clientID = "zig-daper",
            .clientName = "zig-dap-client",
            .adapterID = "go",
            .pathFormat = "path",
            .linesStartAt1 = true,
            .columnsStartAt1 = true,
            .supportsVariableType = true,
            .supportsVariablePaging = true,
            .supportsRunInTerminalRequest = true,
        });

        try connection.?.writeAll(init_request);
        try stdout.print("Sent initialize request\n", .{});
        const response = try self.receiveResponse();
        try stdout.print("Received response: {s}\n", .{response});
    }

    pub fn close(_: *const Client) void {
        connection.?.close();
    }

    fn buildRequest(self: *const Client, seq: u32, command: []const u8, arguments: anytype) ![]const u8 {
        const json = try std.json.stringifyAlloc(
            self.allocator,
            .{
                .seq = seq,
                .type = "request",
                .command = command,
                .arguments = arguments,
            },
            .{},
        );
        defer self.allocator.free(json);

        const content_length = try std.fmt.allocPrint(self.allocator, "Content-Length: {}\r\n\r\n", .{json.len});
        defer self.allocator.free(content_length);
        return try std.mem.concat(self.allocator, u8, &.{ content_length, json });
    }

    fn receiveResponse(
        self: *const Client,
    ) ![]const u8 {
        const reader = connection.?.reader();

        var header: [256]u8 = undefined;
        var header_len: usize = 0;

        while (header_len < header.len) {
            const byte = try reader.readByte();
            header[header_len] = byte;
            header_len += 1;

            if (header_len >= 4 and std.mem.endsWith(u8, header[0..header_len], "\r\n\r\n")) {
                break;
            }
        }

        const header_str = header[0..header_len];
        const content_length_start = std.mem.indexOf(u8, header_str, "Content-Length: ");
        if (content_length_start == null) return error.InvalidHeader;

        const content_length_end = std.mem.indexOf(u8, header_str[content_length_start.? + 16 ..], "\r\n");
        if (content_length_end == null) return error.InvalidHeader;

        const content_length_str = header_str[content_length_start.? + 16 .. content_length_start.? + 16 + content_length_end.?];
        const content_length = try std.fmt.parseInt(usize, content_length_str, 10);

        const payload: []u8 = try self.allocator.alloc(u8, content_length);
        _ = try reader.readAll(payload);

        return payload;
    }
};
