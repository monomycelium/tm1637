# tm1637
A `tm1637` driver for Linux, based on [depklyon/raspberrypi-tm1637](https://github.com/depklyon/raspberrypi-tm1637) and [phip1611/generic-tm1637-gpio-driver-rust](https://github.com/phip1611/generic-tm1637-gpio-driver-rust).

## acknowledgements
This library is only possible with [the Linux userspace ABI for GPIO character devices](https://github.com/torvalds/linux/blob/master/include/uapi/linux/gpio.h) and its wise documentation! The simple Python library, [depklyon/raspberrypi-tm1637](https://github.com/depklyon/raspberrypi-tm1637), helped me figure out how to interface the TM1637 display.

## building
To use this library, ensure you have Linux userspace headers installed, specifically `<linux/gpio.h>`, and have the latest (master) [Zig toolchain](https://ziglang.org/download/) set up. Then, build it from the root of the repository:
``` bash
zig build -Doptimize=ReleaseSmall
```

## demo
Once you have built the library, you can try the demo executable at `./zig-out/bin/demo`, which requires the CLK and DIO pins of a TM1637 display to be connected to pins 24 and 11 of `/dev/gpiochip0`, respectively. Then, be amazed by some entertaining random figures shown on display. When that stops, visit [segments](https://cdn.monomarsh.com/segments/) to construct your sequence of characters and paste the bytes to the terminal to see it written on display!
