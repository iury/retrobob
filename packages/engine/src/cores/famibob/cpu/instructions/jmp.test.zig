const testing = @import("../testing/setup.zig");

test "JMP" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x4c);
    cpu.write(1, 0x55);
    cpu.write(2, 0x97);
    for (0..3) |_| {
        cpu.process();
    }
    try testing.expectEqual(0x9755, cpu.pc);
}

test "JMP indirect" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x6c);
    cpu.write(1, 0x55);
    cpu.write(2, 0x97);
    cpu.write(0x9755, 0x42);
    cpu.write(0x9756, 0x55);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(0x5542, cpu.pc);
}

test "JMP indirect + hardware bug" {
    var cpu = testing.createCPU();
    cpu.write(0, 0x6c);
    cpu.write(1, 0xff);
    cpu.write(2, 0x97);
    cpu.write(0x97ff, 0x42);
    cpu.write(0x9700, 0x55);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(0x5542, cpu.pc);
}
