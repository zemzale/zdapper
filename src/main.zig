const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const host = "127.0.0.1";
    const port = 2345;

    const connection = std.net.tcpConnectToHost(allocator, host, port) catch |err| {
        std.log.err("failed to connect to {s}:{d}: {s}", .{ host, port, @errorName(err) });
        return;
    };

    defer connection.close();

    const stdout = std.io.getStdOut().writer();

    const initialize_request = try buildRequest(allocator, 1, "initialize", .{
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

    try connection.writeAll(initialize_request);
    try stdout.print("Sent initialize request\n", .{});

    const response = try receiveResponse(allocator, connection);
    defer allocator.free(response);
    try stdout.print("Received response: {s}\n", .{response});
}

fn buildRequest(allocator: std.mem.Allocator, seq: u32, command: []const u8, arguments: anytype) ![]const u8 {
    const json = try std.json.stringifyAlloc(
        allocator,
        .{
            .seq = seq,
            .type = "request",
            .command = command,
            .arguments = arguments,
        },
        .{},
    );
    defer allocator.free(json);

    const content_length = try std.fmt.allocPrint(allocator, "Content-Length: {}\r\n\r\n", .{json.len});
    defer allocator.free(content_length);
    return try std.mem.concat(allocator, u8, &.{ content_length, json });
}

fn receiveResponse(allocator: std.mem.Allocator, connection: std.net.Stream) ![]const u8 {
    const reader = connection.reader();

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

    const payload: []u8 = try allocator.alloc(u8, content_length);
    _ = try reader.readAll(payload);

    return payload;
}
