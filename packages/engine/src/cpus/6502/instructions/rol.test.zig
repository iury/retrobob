const testing = @import("../testing/setup.zig");

test "ROL acc" {
    var cpu = testing.createCPU();
    cpu.acc = 0x80;
    cpu.c = true;
    cpu.write(0, 0x2a);
    for (0..2) |_| {
        cpu.process();
    }
    try testing.expectEqual(true, cpu.c);
    try testing.expectEqual(1, cpu.acc);
}

test "ROL zpg" {
    var cpu = testing.createCPU();
    cpu.acc = 0x80;
    cpu.write(0, 0x26);
    cpu.write(1, 2);
    cpu.write(2, 4);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(8, cpu.read(2));
}

test "ROL abs" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x2e);
    cpu.write(1, 2);
    cpu.write(2, 0xff);
    cpu.write(0xff02, 4);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(8, cpu.read(0xff02));
}
