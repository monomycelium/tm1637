//! This module provides a high-level interface to manipulate GPIO character
//! devices using the Linux userspace ABI.

const std = @import("std");
const uapi = @import("uapi.zig");

const os = std.os;
const mem = std.mem;
const fs = std.fs;

/// Errors that may occur.
pub const GpioError = os.FStatAtError || error{ NotCharDev, InvalidCharDev, PinInUse, PinRequestError } || fs.File.OpenError || os.RealPathError;
/// Pin offset type.
pub const Offset = u6; // TODO: change to u32, without affecting `LineRequest`.

pub const GpioChip = struct {
    //! This struct provides functions for accessing GPIO chips.

    const Self = @This();

    /// The file descriptor of an open chip.
    file: os.fd_t,

    /// Returns a `GpioChip` by opening a GPIO chip and checking whether it
    /// is valid.
    pub fn open(path: [*:0]const u8) !Self {
        try checkPath(path); // check for valid chip
        const file = try fs.cwd().openFileZ(
            path,
            .{ .mode = .read_write },
        );

        return Self{ .file = file.handle };
    }

    /// Closes a `GpioChip`. This must only be done after all `GpioPin`
    /// operations have been done (i.e. `GpioPin` should not be accessed after).
    pub fn close(self: *const Self) void {
        os.close(self.file);
    }

    /// Request a slice of `GpioPin`s. This is helpful for initialising
    /// multiple pins at once. `offsets` is a slice of offsets that will be
    /// requested. A slice of `GpioPin`s with the same length as `offsets`
    /// must be passed.
    pub fn getPins(
        self: *Self,
        label: []const u8,
        offsets: []const Offset,
        pins: []GpioPin,
        dir: GpioPin.Direction,
        val: GpioPin.Bit,
    ) !void {
        std.debug.assert(offsets.len < uapi.GPIO_V2_LINES_MAX);
        std.debug.assert(offsets.len == pins.len);

        var request = mem.zeroes(uapi.LineRequest);
        request.num_lines = @truncate(offsets.len);
        request.config.flags |= uapi.GPIO_V2_LINE_FLAG_INPUT << @intFromEnum(dir);
        request.config.num_attrs = 1;
        request.config.attrs[0].attr.id = uapi.GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
        mem.copyForwards(u8, &request.consumer, label);

        for (offsets, 0..) |offset, i| {
            const index: Offset = @truncate(i);
            request.offsets[i] = offset;
            request.config.attrs[0].attr.attr.values |= @as(u64, @intFromEnum(val)) << index; // set default value
            request.config.attrs[0].mask |= @as(u64, 1) << index;
        }

        switch (os.errno(std.c.ioctl(
            self.file,
            uapi.GPIO_V2_GET_LINE_IOCTL,
            &request,
        ))) {
            .SUCCESS => {},
            .BUSY => return error.PinInUse, // Pin used by other consumer.
            else => |e| {
                std.log.err("unexpected errno: {any}\n", .{e});
                unreachable;
            },
        }

        if (request.fd <= 0) return GpioError.PinRequestError;
        for (pins, 0..) |*pin, i|
            pin.* = GpioPin{ .fd = request.fd, .direction = dir, .index = @truncate(i) };
    }

    /// Request a `GpioPin`.
    pub fn getPin(
        self: *Self,
        label: []const u8,
        offset: Offset,
        dir: GpioPin.Direction,
        val: GpioPin.Bit,
    ) !GpioPin {
        var request = mem.zeroes(uapi.LineRequest);
        request.num_lines = 1;
        request.offsets[0] = offset;
        request.config.flags |= uapi.GPIO_V2_LINE_FLAG_INPUT << @intFromEnum(dir);
        request.config.num_attrs = 1;
        request.config.attrs[0].attr.id = uapi.GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
        request.config.attrs[0].attr.attr.values = @intFromEnum(val); // set default value
        request.config.attrs[0].mask = 1;
        mem.copyForwards(u8, &request.consumer, label);

        switch (os.errno(std.c.ioctl(
            self.file,
            uapi.GPIO_V2_GET_LINE_IOCTL,
            &request,
        ))) {
            .SUCCESS => {},
            .BUSY => return error.PinInUse, // Pin used by other consumer.
            else => |e| {
                std.log.err("unexpected errno: {any}\n", .{e});
                unreachable;
            },
        }

        if (request.fd <= 0) return GpioError.PinRequestError;
        return GpioPin{ .fd = request.fd, .direction = dir, .index = 0 };
    }

    inline fn major(rdev: os.dev_t) u32 {
        return @intCast(rdev >> 8);
    }

    inline fn minor(rdev: os.dev_t) u32 {
        return @intCast(rdev & 0xFF);
    }

    /// Checks whether file at `path` is a valid GPIO character device.
    inline fn checkPath(path: [*:0]const u8) !void {
        const stat: os.Stat = try os.fstatatZ(
            fs.cwd().fd,
            path,
            os.AT.NO_AUTOMOUNT,
        );

        // not a character device
        if (!os.linux.S.ISCHR(stat.mode))
            return error.NotCharDev;

        // check for association with gpio subsystem
        var dev: [fs.MAX_PATH_BYTES]u8 = undefined;
        const dev_long: [:0]u8 = try std.fmt.bufPrintZ(
            &dev,
            "/sys/dev/char/{d}:{d}/subsystem",
            .{ major(stat.rdev), minor(stat.rdev) },
        );
        var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
        const dev_path: []u8 = try os.realpath(dev_long, &buf);
        if (!mem.eql(u8, "/sys/bus/gpio", dev_path))
            return error.InvalidCharDev;
    }
};

pub const GpioPin = struct {
    //! This struct represents a GPIO pin and provides functions for it.

    /// Representaiton of direction of the pin.
    pub const Direction = enum { Input, Output };

    /// Simple representation of a pin's value.
    pub const Bit = enum(u1) {
        Low,
        High,

        /// Toggle a bit and return it.
        pub inline fn toggle(self: *Bit) Bit {
            return @enumFromInt(@intFromBool(@intFromEnum(self.*) == 0));
        }
    };

    /// The direction of the pin.
    direction: Direction,
    /// The file descriptor of the request the pin belongs to.
    fd: os.fd_t,
    /// The index into the request the pin belongs to.
    index: Offset,

    /// Closes a `GpioPin`. The `GpioPin` must not be used afterwards, and
    /// other `GpioPin`s that belong to the same request must not be used
    /// or even closed afterwards.
    pub fn close(s: GpioPin) void {
        os.close(s.fd);
    }

    /// Sets a `GpioPin` to `val`. The `GpioPin` must be set to `.Output`.
    pub fn pinSet(pin: GpioPin, val: GpioPin.Bit) void {
        const data = uapi.LineValues.new(pin, val);

        switch (os.errno(std.c.ioctl(
            pin.fd,
            uapi.GPIO_V2_LINE_SET_VALUES_IOCTL,
            &data,
        ))) {
            .SUCCESS => {},
            else => |e| {
                std.log.err("unexpected errno: {any}\n", .{e});
                unreachable;
            },
        }
    }
};

test "check" {
    GpioChip.checkPath("src/demo.zig") catch |err| {
        try std.testing.expectEqual(err, error.NotCharDev);
    };

    GpioChip.checkPath("/dev/tty1") catch |err| {
        try std.testing.expectEqual(err, error.InvalidCharDev);
    };

    GpioChip.checkPath("/dev/gpiochip0") catch unreachable;
}
