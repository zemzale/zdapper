const std = @import("std");
const lib = @import("zdapper_lib");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const host = "127.0.0.1";
    const port: u16 = 2345;

    const c = lib.Client.init(allocator, host, port);
    defer c.close();

    try c.connect();
}
