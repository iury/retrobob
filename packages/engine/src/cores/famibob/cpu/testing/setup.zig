const std = @import("std");
const BufferMapper = @import("BufferMapper.zig");
const DummyDMC = @import("DummyDMC.zig");
const CPU = @import("../cpu.zig").CPU;

pub const expect = std.testing.expect;
pub const expectEqual = std.testing.expectEqual;

pub fn createCPU() CPU {
    const S = struct {
        var buf = BufferMapper{};
        var dmc = DummyDMC{};
    };

    return .{
        .memory = S.buf.memory(),
        .dmc = S.dmc.proxy(),
    };
}
