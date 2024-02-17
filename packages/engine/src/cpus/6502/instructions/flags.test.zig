const testing = @import("../testing/setup.zig");

test "clear instructions" {
    var cpu = testing.createCPU();
    cpu.c = true;
    cpu.i = true;
    cpu.v = true;
    cpu.write(0, 0x18); // CLC
    cpu.write(1, 0xd8); // CLD
    cpu.write(2, 0x58); // CLI
    cpu.write(3, 0xb8); // CLV
    for (0..8) |_| {
        cpu.process();
    }
    try testing.expect(!cpu.c and !cpu.i and !cpu.v);
}

test "set instructions" {
    var cpu = testing.createCPU();
    cpu.c = false;
    cpu.i = false;
    cpu.write(0, 0x38); // SEC
    cpu.write(1, 0xf8); // SED
    cpu.write(2, 0x78); // SEI
    for (0..6) |_| {
        cpu.process();
    }
    try testing.expect(cpu.c and cpu.i);
}
