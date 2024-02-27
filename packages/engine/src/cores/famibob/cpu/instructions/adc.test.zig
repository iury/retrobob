const testing = @import("../testing/setup.zig");

test "ADC imm" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.write(0, 0x69);
    cpu.write(1, 3);
    for (0..2) |_| {
        cpu.process();
    }
    try testing.expectEqual(5, cpu.acc);
}

test "ADC abs" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.write(0, 0x6d);
    cpu.write(1, 3);
    cpu.write(2, 0);
    cpu.write(3, 1);
    for (0..4) |_| {
        cpu.process();
    }
    try testing.expectEqual(3, cpu.acc);
}

test "ADC abx" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.x = 2;
    cpu.write(0, 0x7d);
    cpu.write(1, 1);
    cpu.write(2, 0);
    cpu.write(3, 1);
    for (0..4) |_| {
        cpu.process();
    }
    try testing.expectEqual(3, cpu.acc);
}

test "ADC abx + page crossing" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.x = 1;
    cpu.write(0, 0x7d);
    cpu.write(1, 0xff);
    cpu.write(2, 0);
    cpu.write(0x100, 3);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(5, cpu.acc);
}

test "ADC aby" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.y = 2;
    cpu.write(0, 0x79);
    cpu.write(1, 1);
    cpu.write(2, 0);
    cpu.write(3, 1);
    for (0..4) |_| {
        cpu.process();
    }
    try testing.expectEqual(3, cpu.acc);
}

test "ADC zpg" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.write(0, 0x65);
    cpu.write(1, 2);
    cpu.write(2, 1);
    for (0..3) |_| {
        cpu.process();
    }
    try testing.expectEqual(3, cpu.acc);
}

test "ADC zpx" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.x = 1;
    cpu.write(0, 0x75);
    cpu.write(1, 2);
    cpu.write(2, 0);
    cpu.write(3, 1);
    for (0..4) |_| {
        cpu.process();
    }
    try testing.expectEqual(3, cpu.acc);
}

test "ADC idx" {
    var cpu = testing.createCPU();
    cpu.acc = 5;
    cpu.x = 1;
    cpu.write(0, 0x61);
    cpu.write(1, 0xff);
    cpu.write(4, 2);
    cpu.write(5, 0xff);
    cpu.write(0xff02, 3);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(5, cpu.acc);
}

test "ADC idy" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.y = 1;
    cpu.write(0, 0x71);
    cpu.write(1, 0xfe);
    cpu.write(0xfe, 2);
    cpu.write(0xff, 0xff);
    cpu.write(0xff03, 3);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(5, cpu.acc);
}

test "ADC idy + page crossing" {
    var cpu = testing.createCPU();
    cpu.acc = 2;
    cpu.y = 1;
    cpu.write(0, 0x71);
    cpu.write(1, 0xfe);
    cpu.write(0xfe, 0xff);
    cpu.write(0xff, 0xef);
    cpu.write(0xf000, 3);
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expectEqual(5, cpu.acc);
}
