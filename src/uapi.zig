// Copyright (C) 2023 Mashrafi Rahman
// See end of file for extended copyright information.

//! This module contains pre-defined `structs` and imported macros for the
//! Linux userspace ABI for GPIO character devices.
//! See https://github.com/torvalds/linux/blob/master/include/uapi/linux/gpio.h.

// TODO: Improve documentation.
// TODO: Define more structs (for wider use-cases).
// TODO: Add more methods to structs.

const gpio = @import("gpio.zig");
const std = @import("std");
const os = std.os;
const mem = std.mem;
const c = @cImport({
    @cInclude("linux/gpio.h"); // system UAPI header
});

/// Imported macros and constants from ABI.
pub const GPIO_V2_LINE_SET_VALUES_IOCTL = c.GPIO_V2_LINE_SET_VALUES_IOCTL;
pub const GPIO_V2_GET_LINE_IOCTL = c.GPIO_V2_GET_LINE_IOCTL;
pub const GPIO_V2_LINE_NUM_ATTRS_MAX = c.GPIO_V2_LINE_NUM_ATTRS_MAX;
pub const GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES = c.GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
pub const GPIO_V2_LINES_MAX = c.GPIO_V2_LINES_MAX;
pub const GPIO_MAX_NAME_SIZE = c.GPIO_MAX_NAME_SIZE;
pub const GPIO_V2_LINE_FLAG_INPUT = c.GPIO_V2_LINE_FLAG_INPUT;

pub const LineValues = extern struct {
    //! Values of GPIO lines.

    const Self = @This();

    /// A bitmap containing the value of the lines, set to 1 for active and 0
    /// for inactive.
    bits: u64,
    /// A bitmap identifying the lines to get or set, with each bit number
    /// corresponding to the index into `LineRequest.offsets`.
    mask: u64,

    /// Returns `LineValues` initialised to set `pin` to `val`.
    pub inline fn new(pin: gpio.GpioPin, val: gpio.GpioPin.Bit) Self {
        std.debug.assert(pin.direction == gpio.GpioPin.Direction.Output);
        return LineValues{
            .bits = @as(u64, @enumToInt(val)) << pin.index,
            .mask = @as(u64, 1) << pin.index,
        };
    }

    /// Sets a `pin` to `val`.
    pub inline fn set(self: *LineValues, pin: gpio.GpioPin, val: gpio.GpioPin.Bit) void {
        std.debug.assert(pin.direction == gpio.GpioPin.Direction.Output);
        self.bits |= (1 << pin.index);
        self.mask |= (@as(u64, @enumToInt(val)) << pin.index);
    }
};

pub const LineAttr = extern struct {
    //! A configurable attribute of a line.

    id: u32,
    padding: u32,
    attr: extern union {
        flags: u64,
        values: u64,
        debounce_period_us: u32,
    },
};

pub const LineConfigAttribute = extern struct {
    //! A configuration attribute associated with one or more of the requested
    //! lines.

    /// The configurable attribute.
    attr: LineAttr,
    /// A bitmap identifying the lines to which the attribute applies, with
    /// each bit number corresponding to the index into `LineRequest.offsets`.
    mask: u64,
};

pub const LineConfig = extern struct {
    //! Configuration for GPIO lines.

    flags: u64,
    num_attrs: u32,
    padding: [5]u32,
    attrs: [GPIO_V2_LINE_NUM_ATTRS_MAX]LineConfigAttribute,
};

pub const LineRequest = extern struct {
    //! Information about a request for GPIO lines.

    const Self = @This();

    /// An array of desired lines, specified by offset index for the associated
    /// GPIO chip.
    offsets: [GPIO_V2_LINES_MAX]u32,
    /// A desired consumer label for the selected GPIO lines such as
    /// "my-bitbanged-relay".
    consumer: [GPIO_MAX_NAME_SIZE]u8,
    /// Requested configuration for the lines.
    config: LineConfig,
    /// Number of lines requested in this request, i.e. the number of valid
    /// fields in `offsets`, set to 1 to request a single line.
    num_lines: u32,
    /// A suggested minimum number of line events that the kernel should buffer.
    /// This is only relevant if edge detection is enabled in the configuration.
    /// Note that this is only a suggested value and the kernel may allocate a
    /// larger buffer or cap the size of the buffer. If this field is zero then
    /// the buffer size defaults to a minimum of `num_lines` * 16.
    event_buffer_size: u32,
    /// Implcit padding; reserved for future use and must be zero-filled.
    padding: [5]u32,
    /// If successful, this field will contain a valid anonymous file handle
    /// after a `GPIO_GET_LINE_IOCTL` operation, zero or negative value means
    /// error.
    fd: i32,
};

// `gpio.zig` provides a high-level interface to manipulate GPIO devices using
// the Linux userspace ABI for the GPIO character devices.
// Copyright (C) 2023 Mashrafi Rahman
//
// This file is part of `gpio.zig`.
//
// This file includes code derived from <linux/gpio.h> from the Linux UAPI,
// which is copyrighted by Linus Walleij and licensed under the GNU General
// Public License version 2.
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 2 as published by
// the Free Software Foundation.
