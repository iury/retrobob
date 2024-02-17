const std = @import("std");
const Clock = @import("clock.zig").Clock;
const Famibob = @import("famibob.zig").Famibob;

test "Famibob NTSC clock" {
    const S = struct {
        cpu: u32 = 0,
        ppu: u32 = 0,
        pub fn handleCPUCycle(self: *@This()) void {
            self.cpu += 1;
        }
        pub fn handlePPUCycle(self: *@This()) void {
            self.ppu += 1;
        }
    };

    var s = S{};
    var clock = Clock(S, .ntsc){ .handler = &s };

    for (0..60) |_| {
        clock.run(.frame);
    }

    try std.testing.expectApproxEqAbs(29780.3, @as(f64, @floatFromInt(s.cpu)) / 60.0, 0.05);
    try std.testing.expectApproxEqAbs(89341, @as(f64, @floatFromInt(s.ppu)) / 60.0, 0.05);
}

test "Famibob PAL clock" {
    const S = struct {
        cpu: u32 = 0,
        ppu: u32 = 0,
        pub fn handleCPUCycle(self: *@This()) void {
            self.cpu += 1;
        }
        pub fn handlePPUCycle(self: *@This()) void {
            self.ppu += 1;
        }
    };

    var s = S{};
    var clock = Clock(S, .pal){ .handler = &s };

    for (0..60) |_| {
        clock.run(.frame);
    }

    try std.testing.expectApproxEqAbs(33247.5, @as(f64, @floatFromInt(s.cpu)) / 60.0, 0.05);
    try std.testing.expectApproxEqAbs(106392.0, @as(f64, @floatFromInt(s.ppu)) / 60.0, 0.05);
}
