const std = @import("std");
const opcode = @import("opcode.zig");
const Memory = @import("../../../memory.zig").Memory;
const Proxy = @import("../../../proxy.zig").Proxy;
const irq = @import("instructions/irq.zig").irq;
const c = @import("../../../c.zig");

pub const CPUCycle = enum { finished, addressing, read, write };

pub const DMACycle = enum { get, put };

pub const DMAStatus = enum { idle, halting, alignment, dmc_dummy_read, cpu_halted };

pub const CPU = struct {
    opcode: u8 = 0,
    addressing: opcode.Addressing = .imp,
    cycle_counter: u8 = 0,
    current_cycle: CPUCycle = .finished,
    next_cycle: CPUCycle = .finished,

    dmc_dma: bool = false,
    oam_dma: bool = false,
    dma_status: DMAStatus = .idle,
    dma_cycle: DMACycle = .get,
    dmc_address: u16 = 0,
    oam_address: u16 = 0,
    oam_counter: u8 = 0,
    oam_value: u8 = 0,

    pc: u16 = 0,
    sp: u8 = 0,
    acc: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,

    c: bool = false,
    z: bool = false,
    i: bool = true,
    d: bool = false,
    b: bool = false,
    v: bool = false,
    n: bool = false,

    irq_occurred: bool = false,
    nmi_requested: bool = false,
    rst_requested: bool = false,
    irq_requested: bool = false,

    memory: Memory(u16, u8),
    dmc: Proxy(u8),

    pub inline fn read(self: *CPU, address: u16) u8 {
        return self.memory.read(address);
    }

    pub inline fn write(self: *CPU, address: u16, value: u8) void {
        self.memory.write(address, value);
    }

    pub fn getP(self: *const CPU) u8 {
        return 0x20 |
            (if (self.c) @as(u8, 0x01) else 0) |
            (if (self.z) @as(u8, 0x02) else 0) |
            (if (self.i) @as(u8, 0x04) else 0) |
            (if (self.d) @as(u8, 0x08) else 0) |
            (if (self.b) @as(u8, 0x10) else 0) |
            (if (self.v) @as(u8, 0x40) else 0) |
            (if (self.n) @as(u8, 0x80) else 0);
    }

    pub fn setP(self: *CPU, value: u8) void {
        self.c = (value & 0x01) > 0;
        self.z = (value & 0x02) > 0;
        self.i = (value & 0x04) > 0;
        self.d = (value & 0x08) > 0;
        self.b = (value & 0x10) > 0;
        self.v = (value & 0x40) > 0;
        self.n = (value & 0x80) > 0;
    }

    pub fn fetch(self: *CPU) u8 {
        const value = self.read(self.pc);
        self.pc +%= 1;
        return value;
    }

    fn fetchOpcode(self: *CPU) void {
        self.cycle_counter = 1;
        self.addressing = .imp;
        self.current_cycle = .read;
        self.next_cycle = .addressing;
        self.opcode = self.fetch();
    }

    fn handleDMA(self: *CPU) bool {
        const dummy = struct {
            pub fn read(cpu: *CPU) void {
                _ = cpu.fetch();
                cpu.pc -%= 1;
            }
        };

        if (self.dma_status == .halting) {
            if (self.next_cycle != .write) {
                dummy.read(self);
                self.dma_status = if (self.dmc_dma) .dmc_dummy_read else .alignment;
                return true;
            }
        } else if (self.dma_status == .dmc_dummy_read) {
            dummy.read(self);
            self.dma_status = .alignment;
            return true;
        } else if (self.dma_status == .alignment) {
            if (self.dma_cycle == .put) {
                dummy.read(self);
                return true;
            } else {
                self.dma_status = .cpu_halted;
            }
        }

        if (self.dma_status == .cpu_halted) {
            if (self.dmc_dma) {
                self.dmc.set(self.read(self.dmc_address));
                self.dmc_dma = false;
                self.dma_status = if (self.oam_dma) .alignment else .idle;
            } else if (self.oam_dma) {
                if (self.dma_cycle == .get) {
                    self.oam_value = self.read(self.oam_address | self.oam_counter);
                } else {
                    self.write(0x2004, self.oam_value);
                    self.oam_counter +%= 1;
                    if (self.oam_counter == 0) {
                        self.oam_dma = false;
                        self.dma_status = .idle;
                    }
                }
            }
            return true;
        }

        return false;
    }

    pub fn checkPageCrossing(address: u16, offset: u8) bool {
        return (address & 0xff00) != ((address +% offset) & 0xff00);
    }

    fn resolveAddressing(self: *CPU) bool {
        const inst = opcode.Opcodes[self.opcode];
        self.current_cycle = .read;
        self.next_cycle = .read;

        switch (inst.addressing_mode) {
            .ind, .imp => {},

            .acc => {
                self.addressing = .acc;
                return false;
            },

            .imm => {
                self.addressing = .{ .imm = self.fetch() };
                return false;
            },

            .rel => {
                self.addressing = .{ .rel = @bitCast(self.fetch()) };
                return false;
            },

            .zpg => {
                switch (self.addressing) {
                    .zpg => {},
                    else => {
                        self.addressing = .{ .zpg = self.fetch() };
                        return true;
                    },
                }
            },

            .zpx => {
                switch (self.addressing) {
                    .zpx => |v| {
                        if (self.cycle_counter == 3) {
                            _ = self.read(v);
                            return true;
                        } else {
                            self.addressing = .{ .zpx = v +% self.x };
                            return false;
                        }
                    },
                    else => {
                        self.addressing = .{ .zpx = self.fetch() };
                        return true;
                    },
                }
            },

            .zpy => {
                switch (self.addressing) {
                    .zpy => |v| {
                        if (self.cycle_counter == 3) {
                            _ = self.read(v);
                            return true;
                        } else {
                            self.addressing = .{ .zpy = v +% self.y };
                            return false;
                        }
                    },
                    else => {
                        self.addressing = .{ .zpy = self.fetch() };
                        return true;
                    },
                }
            },

            .abs => {
                switch (self.addressing) {
                    .abs => |v| {
                        if (self.cycle_counter == 3) {
                            self.addressing = .{ .abs = v | (@as(u16, self.fetch()) << 8) };
                            return true;
                        }
                    },
                    else => {
                        self.addressing = .{ .abs = self.fetch() };
                        return true;
                    },
                }
            },

            .abx => {
                switch (self.addressing) {
                    .abx => |v| {
                        const addr = v.@"0";
                        if (self.cycle_counter == 3) {
                            self.addressing = .{ .abx = .{ addr | (@as(u16, self.fetch()) << 8), false } };
                            return true;
                        } else if (self.cycle_counter == 4) {
                            if (checkPageCrossing(addr, self.x)) {
                                self.addressing = .{ .abx = .{ addr +% self.x, true } };
                                _ = self.read((addr & 0xff00) | ((addr +% self.x) & 0xff));
                                return true;
                            } else {
                                self.addressing = .{ .abx = .{ addr +% self.x, false } };
                                return false;
                            }
                        }
                    },
                    else => {
                        self.addressing = .{ .abx = .{ self.fetch(), false } };
                        return true;
                    },
                }
            },

            .aby => {
                switch (self.addressing) {
                    .aby => |v| {
                        const addr = v.@"0";
                        if (self.cycle_counter == 3) {
                            self.addressing = .{ .aby = .{ addr | (@as(u16, self.fetch()) << 8), false } };
                            return true;
                        } else if (self.cycle_counter == 4) {
                            if (checkPageCrossing(addr, self.y)) {
                                self.addressing = .{ .aby = .{ addr +% self.y, true } };
                                _ = self.read((addr & 0xff00) | ((addr +% self.y) & 0xff));
                                return true;
                            } else {
                                self.addressing = .{ .aby = .{ addr +% self.y, false } };
                                return false;
                            }
                        }
                    },
                    else => {
                        self.addressing = .{ .aby = .{ self.fetch(), false } };
                        return true;
                    },
                }
            },

            .idx => {
                switch (self.addressing) {
                    .idx => |v| {
                        if (self.cycle_counter == 3) {
                            _ = self.read(v.@"1");
                            self.addressing = .{ .idx = .{ 0, v.@"1" +% self.x } };
                            return true;
                        } else if (self.cycle_counter == 4) {
                            const addr = self.read(v.@"1");
                            self.addressing = .{ .idx = .{ addr, v.@"1" } };
                            return true;
                        } else if (self.cycle_counter == 5) {
                            var addr = v.@"0";
                            addr |= @as(u16, self.read(v.@"1" +% 1)) << 8;
                            self.addressing = .{ .idx = .{ addr, 0 } };
                            return true;
                        }
                    },
                    else => {
                        self.addressing = .{ .idx = .{ 0, self.fetch() } };
                        return true;
                    },
                }
            },

            .idy => {
                switch (self.addressing) {
                    .idy => |v| {
                        if (self.cycle_counter == 3) {
                            const addr = self.read(v.@"1");
                            self.addressing = .{ .idy = .{ addr, v.@"1", false } };
                            return true;
                        } else if (self.cycle_counter == 4) {
                            var addr = v.@"0";
                            addr |= @as(u16, self.read(v.@"1" +% 1)) << 8;
                            self.addressing = .{ .idy = .{ addr, 0, false } };
                            return true;
                        } else if (self.cycle_counter == 5) {
                            const addr = v.@"0";
                            if (checkPageCrossing(v.@"0", self.y)) {
                                _ = self.read((addr & 0xff00) | ((addr +% self.y) & 0xff));
                                self.addressing = .{ .idy = .{ addr +% self.y, 0, true } };
                                return true;
                            } else {
                                self.addressing = .{ .idy = .{ addr +% self.y, 0, false } };
                                return false;
                            }
                        }
                    },
                    else => {
                        self.addressing = .{ .idy = .{ 0, self.fetch(), false } };
                        return true;
                    },
                }
            },
        }

        return false;
    }

    pub fn process(self: *CPU) void {
        self.dma_cycle = if (self.dma_cycle == .get) .put else .get;

        if (self.dma_status == .idle and (self.oam_dma or self.dmc_dma)) {
            self.oam_counter = 0;
            self.dma_status = .halting;
        }

        if (self.dma_status != .idle) {
            if (self.handleDMA()) return;
        }

        self.current_cycle = self.next_cycle;

        if (self.current_cycle == .finished) {
            if (self.irq_requested and self.i) self.irq_requested = false;
            if (self.rst_requested or self.nmi_requested or self.irq_requested) {
                self.irq_occurred = true;
            }
            if (self.irq_occurred) {
                irq(self);
                return;
            }

            self.fetchOpcode();
            return;
        }

        self.cycle_counter += 1;

        const inst = opcode.Opcodes[self.opcode];

        if (self.current_cycle == .addressing and inst.instruction != .jmp) {
            if (self.resolveAddressing()) {
                self.next_cycle = .addressing;
                return;
            }
        }

        self.next_cycle = .finished;
        inst.func(self, self.addressing);
    }

    pub fn reset(self: *CPU) void {
        self.opcode = 0;
        self.addressing = .imp;
        self.cycle_counter = 0;
        self.current_cycle = .finished;
        self.next_cycle = .finished;
        self.dmc_dma = false;
        self.oam_dma = false;
        self.dma_status = .idle;
        self.dma_cycle = .get;
        self.dmc_address = 0;
        self.oam_address = 0;
        self.oam_counter = 0;
        self.oam_value = 0;
        self.pc = 0;
        self.sp = 0;
        self.acc = 0;
        self.x = 0;
        self.y = 0;
        self.c = false;
        self.z = false;
        self.i = true;
        self.d = false;
        self.b = false;
        self.v = false;
        self.n = false;
        self.irq_occurred = false;
        self.nmi_requested = false;
        self.rst_requested = false;
        self.irq_requested = false;
    }

    pub fn serialize(self: *const CPU, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "addressing");
        c.mpack_build_array(pack);
        switch (self.addressing) {
            .imp => {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.imp));
            },
            .acc => {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.acc));
            },
            .rel => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.rel));
                c.mpack_write_i8(pack, v);
            },
            .imm => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.imm));
                c.mpack_write_u8(pack, v);
            },
            .zpg => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.zpg));
                c.mpack_write_u8(pack, v);
            },
            .zpx => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.zpx));
                c.mpack_write_u8(pack, v);
            },
            .zpy => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.zpy));
                c.mpack_write_u8(pack, v);
            },
            .abs => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.abs));
                c.mpack_write_u16(pack, v);
            },
            .abx => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.abx));
                c.mpack_write_u16(pack, v.@"0");
                c.mpack_write_bool(pack, v.@"1");
            },
            .aby => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.aby));
                c.mpack_write_u16(pack, v.@"0");
                c.mpack_write_bool(pack, v.@"1");
            },
            .idx => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.idx));
                c.mpack_write_u16(pack, v.@"0");
                c.mpack_write_u8(pack, v.@"1");
            },
            .idy => |v| {
                c.mpack_write_u8(pack, @intFromEnum(opcode.AddressingMode.idy));
                c.mpack_write_u16(pack, v.@"0");
                c.mpack_write_u8(pack, v.@"1");
                c.mpack_write_bool(pack, v.@"2");
            },
        }
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "opcode");
        c.mpack_write_u8(pack, self.opcode);
        c.mpack_write_cstr(pack, "cycle_counter");
        c.mpack_write_u8(pack, self.cycle_counter);
        c.mpack_write_cstr(pack, "current_cycle");
        c.mpack_write_u8(pack, @intFromEnum(self.current_cycle));
        c.mpack_write_cstr(pack, "next_cycle");
        c.mpack_write_u8(pack, @intFromEnum(self.next_cycle));
        c.mpack_write_cstr(pack, "dmc_dma");
        c.mpack_write_bool(pack, self.dmc_dma);
        c.mpack_write_cstr(pack, "oam_dma");
        c.mpack_write_bool(pack, self.oam_dma);
        c.mpack_write_cstr(pack, "dma_status");
        c.mpack_write_u8(pack, @intFromEnum(self.dma_status));
        c.mpack_write_cstr(pack, "dma_cycle");
        c.mpack_write_u8(pack, @intFromEnum(self.dma_cycle));
        c.mpack_write_cstr(pack, "dmc_address");
        c.mpack_write_u16(pack, self.dmc_address);
        c.mpack_write_cstr(pack, "oam_address");
        c.mpack_write_u16(pack, self.oam_address);
        c.mpack_write_cstr(pack, "oam_counter");
        c.mpack_write_u8(pack, self.oam_counter);
        c.mpack_write_cstr(pack, "oam_value");
        c.mpack_write_u8(pack, self.oam_value);
        c.mpack_write_cstr(pack, "pc");
        c.mpack_write_u16(pack, self.pc);
        c.mpack_write_cstr(pack, "sp");
        c.mpack_write_u8(pack, self.sp);
        c.mpack_write_cstr(pack, "acc");
        c.mpack_write_u8(pack, self.acc);
        c.mpack_write_cstr(pack, "x");
        c.mpack_write_u8(pack, self.x);
        c.mpack_write_cstr(pack, "y");
        c.mpack_write_u8(pack, self.y);
        c.mpack_write_cstr(pack, "c");
        c.mpack_write_bool(pack, self.c);
        c.mpack_write_cstr(pack, "z");
        c.mpack_write_bool(pack, self.z);
        c.mpack_write_cstr(pack, "i");
        c.mpack_write_bool(pack, self.i);
        c.mpack_write_cstr(pack, "d");
        c.mpack_write_bool(pack, self.d);
        c.mpack_write_cstr(pack, "b");
        c.mpack_write_bool(pack, self.b);
        c.mpack_write_cstr(pack, "v");
        c.mpack_write_bool(pack, self.v);
        c.mpack_write_cstr(pack, "n");
        c.mpack_write_bool(pack, self.n);
        c.mpack_write_cstr(pack, "irq_occurred");
        c.mpack_write_bool(pack, self.irq_occurred);
        c.mpack_write_cstr(pack, "nmi_requested");
        c.mpack_write_bool(pack, self.nmi_requested);
        c.mpack_write_cstr(pack, "rst_requested");
        c.mpack_write_bool(pack, self.rst_requested);
        c.mpack_write_cstr(pack, "irq_requested");
        c.mpack_write_bool(pack, self.irq_requested);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *CPU, pack: c.mpack_node_t) void {
        const addressing: opcode.AddressingMode = @enumFromInt(c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 0)));
        switch (addressing) {
            .acc => self.addressing = .acc,
            .imp => self.addressing = .imp,
            .rel => self.addressing = .{ .rel = c.mpack_node_i8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)) },
            .imm => self.addressing = .{ .imm = c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)) },
            .zpg => self.addressing = .{ .zpg = c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)) },
            .zpx => self.addressing = .{ .zpx = c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)) },
            .zpy => self.addressing = .{ .zpy = c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)) },
            .abs => self.addressing = .{ .abs = c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)) },
            .abx => self.addressing = .{ .abx = .{
                c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)),
                c.mpack_node_bool(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 2)),
            } },
            .aby => self.addressing = .{ .aby = .{
                c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)),
                c.mpack_node_bool(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 2)),
            } },
            .idx => self.addressing = .{ .idx = .{
                c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)),
                c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 2)),
            } },
            .idy => self.addressing = .{ .idy = .{
                c.mpack_node_u16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 1)),
                c.mpack_node_u8(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 2)),
                c.mpack_node_bool(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "addressing"), 3)),
            } },
            .ind => {},
        }

        self.current_cycle = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "current_cycle")));
        self.next_cycle = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "next_cycle")));
        self.dma_status = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "dma_status")));
        self.dma_cycle = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "dma_cycle")));
        self.opcode = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "opcode"));
        self.cycle_counter = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "cycle_counter"));
        self.dmc_dma = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "dmc_dma"));
        self.oam_dma = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "oam_dma"));
        self.dmc_address = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "dmc_address"));
        self.oam_address = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "oam_address"));
        self.oam_counter = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "oam_counter"));
        self.oam_value = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "oam_value"));
        self.pc = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "pc"));
        self.sp = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "sp"));
        self.acc = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "acc"));
        self.x = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "x"));
        self.y = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "y"));
        self.c = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "c"));
        self.z = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "z"));
        self.i = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "i"));
        self.d = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "d"));
        self.b = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "b"));
        self.v = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "v"));
        self.n = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "n"));
        self.irq_occurred = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_occurred"));
        self.nmi_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "nmi_requested"));
        self.rst_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "rst_requested"));
        self.irq_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_requested"));
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = @import("cpu.test.zig");
    _ = @import("instructions/flags.test.zig");
    // _ = @import("nestest/nestest.test.zig");
}
