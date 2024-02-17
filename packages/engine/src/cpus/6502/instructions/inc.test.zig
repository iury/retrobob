const testing = @import("../testing/setup.zig");

test "INC" {
    var cpu = testing.createCPU();
    cpu.write(0, 0xe6);
    cpu.write(1, 2);
    cpu.write(2, 0xff);
    for (0..5) |_| {
        cpu.process();
    }
    try testing.expectEqual(0, cpu.read(2));
}
