const std = @import("std");
const Tm1637 = @import("Tm1637.zig");

fn run() !void {
    var display = try Tm1637.init("/dev/gpiochip0", 24, 11, 7);
    defer display.deinit();

    // display.write(&[_]u8{ 0x6d, 0x5c, 0x1c, 0x50, 0x44, 0x1c }, 0);

    // print random bytes for a few seconds

    // initialise random seed
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    // update evey few seconds
    for (0..60) |_| {
        var random: [4]u8 = undefined;
        rand.bytes(&random);
        display.write(&random, 0);

        std.os.nanosleep(0, std.time.ns_per_s / 5);
    }

    // read hexadecimal arrays from stdin
    // formatted as 0x00, 0x00, 0x00, 0x00
    var buf: [24]u8 = undefined;
    const stdout = std.io.getStdIn().reader();
    while (try stdout.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var bytes: [4]u8 = comptime std.mem.zeroes([4]u8);

        var iterator = std.mem.splitAny(u8, line, "0x");
        var index: u3 = 0;
        while (iterator.next()) |eek| {
            if (eek.len == 0) continue;
            const delim = std.mem.indexOfScalar(u8, eek, ',') orelse eek.len;
            bytes[index] = std.fmt.parseUnsigned(u8, eek[0..delim], 16) catch continue;
            index += 1;
            if (index == 4) break;
        }

        display.write(&bytes, 0);
        std.debug.print("wrote: {any}\n", .{bytes});
    }
}

pub fn main() void {
    run() catch |err| {
        std.log.err("{any}", .{err});
        std.os.exit(1);
    };
}
