const testing = @import("../testing/setup.zig");

test "LSR acc" {
    var cpu = testing.createCPU();
    cpu.acc = 255;
    cpu.write(0, 0x4a);
    for (0..2) |_| {
        cpu.process();
    }
    try testing.expectEqual(127, cpu.acc);
    try testing.expectEqual(true, cpu.c);
}

test "LSR zpg" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x46);
    cpu.write(1, 2);
    cpu.write(2, 4);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(2, cpu.read(2));
}

test "LSR abs" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x4e);
    cpu.write(1, 2);
    cpu.write(2, 0xff);
    cpu.write(0xff02, 4);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(2, cpu.read(0xff02));
}
