//! This struct provides functions for manipulating a TM1637 display using
//! the Linux userspace ABI for GPIO character devices. It depends on libc to
//! access Linux headers.

const std = @import("std");
const gpio = @import("gpio.zig");
const os = std.os;

const Self = @This();
const Tm1637Error = gpio.GpioError;

/// The number of digits in a TM1637 display.
pub const digits = 4;
/// The number of registers in a TM1637 display. (Some displays only use four.)
pub const registers = 6;
pub const State = enum(u4) { OFF = 0b0000, ON = 0b1000 };

const command_data = 0x40;
const command_addr = 0xc0;
const command_ctrl = 0x80;
const display_sep = 0x80;

/// The GPIO chip connected to the TM1637 display.
gpio_chip: gpio.GpioChip,
/// The GPIO pin connected to the DIO pin of a TM1637 display.
pin_dio: gpio.GpioPin,
/// The GPIO pin connected to the CLK pin of a TM1637 display.
pin_clk: gpio.GpioPin,
/// The desired brightness of the TM1637 as a value between 0 and 7, where 0
/// is the lowest and 7 is the highest. The fourth bit represents whether the
/// display is on or off.
brightness: u4,

/// Initialises the TM1637 display.
///
/// * `gpio_chip` is a null-terminated string representing the GPIO chip used
/// for the TM1637 display, like `/dev/gpiochip0`.
/// * `pin_clk` is the offset (pin number) of the CLK pin on the GPIO chip.
/// * `pin_dio` is the offset (pin number) of the DIO pin on the GPIO chip.
/// * `brightness` indicates the brightness level of the display (0 to 7, with
/// 0 being the lowest and 7 being the highest).
///
pub fn init(
    gpio_chip: [*:0]const u8,
    pin_clk: gpio.Offset,
    pin_dio: gpio.Offset,
    brightness: u3,
) Tm1637Error!Self {
    var chip: gpio.GpioChip = try gpio.GpioChip.open(gpio_chip);
    var pins: [2]gpio.GpioPin = undefined;
    try chip.getPins(
        "Tm1637",
        &[_]gpio.Offset{ pin_clk, pin_dio },
        &pins,
        .Output,
        .Low,
    );

    return Self{
        .brightness = brightness | @intFromEnum(State.ON),
        .gpio_chip = chip,
        .pin_clk = pins[0],
        .pin_dio = pins[1],
    };
}

/// Closes GPIO interface.
pub fn deinit(self: *Self) void {
    self.pin_clk.close();
    // self.pin_dio.close(); // same fd; TODO(gpio): prevent panic.
    self.gpio_chip.close();
}

/// Sends start sequence.
inline fn start(self: *Self) void {
    self.pin_clk.pinSet(.High);
    self.pin_dio.pinSet(.High);
    // os.nanosleep(0, delay_ns);
    self.pin_dio.pinSet(.Low);
    self.pin_clk.pinSet(.Low);
}

/// Sends stop sequence.
inline fn stop(self: *Self) void {
    self.pin_clk.pinSet(.Low);
    self.pin_dio.pinSet(.Low);
    self.pin_clk.pinSet(.High);
    self.pin_dio.pinSet(.High);
}

/// Waits for acknowledgement bit.
/// Reading unimplemented for linux as it seems pointless.
inline fn waitForAck(self: *Self) void {
    self.pin_clk.pinSet(.Low);
    // os.nanosleep(0, delay_ns);
    // while (self.pin_dio.pinRead() != .Low) {}
    self.pin_clk.pinSet(.High);
    // os.nanosleep(0, delay_ns);
    self.pin_clk.pinSet(.Low);
}

/// Writes a byte to the display.
inline fn writeByte(self: *Self, byte: u8) void {
    for (0..8) |i| {
        const bit = (byte >> @truncate(i)) & 1;
        self.pin_dio.pinSet(@enumFromInt(bit));
        self.pin_clk.pinSet(.High);
        // os.nanosleep(0, delay_ns);
        self.pin_clk.pinSet(.Low);
    }

    self.waitForAck();
}

/// Writes a command to the display.
inline fn writeCommand(self: *Self, byte: u8) void {
    self.start();
    self.writeByte(byte);
    self.stop();
}

/// Sets state of TM1637 display (whether it is on or off).
pub fn setState(self: *Self, state: State) void {
    self.brightness |= @intFromEnum(state);
    self.writeCommand(command_data);
    self.writeCommand(command_ctrl | @as(u8, self.brightness));
}

/// Sets brightness of TM1637 display to a value between 0 and 7. (0 being the
/// lowest, and 7 being the highest). Turns display on if it is turned off.
pub fn setBrightness(self: *Self, brightness: u3) void {
    self.brightness = brightness | @intFromEnum(State.ON);
    self.writeCommand(command_data);
    self.writeCommand(command_ctrl | @as(u8, self.brightness));
}

/// Writes bytes (aka segments) into TM1637 segment registers.
/// * `bytes` is a slice of bytes, with each byte representing the segment in
/// each digit, and bits in `<dp>gfedcba` order.
/// * `pos` must be between 0 and 5, representing the position in the display.
pub fn write(self: *Self, bytes: []const u8, pos: u3) void {
    std.debug.assert(pos + bytes.len <= registers); // prevent overflow
    std.debug.assert(bytes.len > 0); // bleh

    self.writeCommand(command_data); // write data command
    self.start();

    self.writeByte(@as(u8, command_addr) | pos); // set position
    for (bytes) |b| self.writeByte(b); // write each byte

    self.stop();
    self.writeCommand(command_ctrl | @as(u8, self.brightness));
}
