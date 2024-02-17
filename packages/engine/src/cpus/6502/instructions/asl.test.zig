const testing = @import("../testing/setup.zig");

test "ASL acc" {
    var cpu = testing.createCPU();
    cpu.acc = 1;
    cpu.write(0, 0x0a);
    for (0..2) |_| {
        cpu.process();
    }
    try testing.expectEqual(2, cpu.acc);
}

test "ASL zpg" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x06);
    cpu.write(1, 2);
    cpu.write(2, 4);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(8, cpu.read(2));
}

test "ASL abs" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x0e);
    cpu.write(1, 2);
    cpu.write(2, 0xff);
    cpu.write(0xff02, 4);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(8, cpu.read(0xff02));
}
