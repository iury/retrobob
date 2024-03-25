const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;
const c = @import("../../c.zig");

const PATTERN: [8][5]u3 = [_][5]u3{
    .{ 1, 0, 0, 0, 0 },
    .{ 2, 0, 1, 0, 1 },
    .{ 2, 0, 0, 0, 0 },
    .{ 4, 0, 0, 1, 1 },
    .{ 4, 0, 1, 2, 3 },
    .{ 4, 0, 1, 0, 1 },
    .{ 2, 0, 0, 0, 0 },
    .{ 4, 0, 0, 1, 1 },
};

fn isWRAMaddress(address: u24) bool {
    return switch (@as(u8, @truncate(address >> 16))) {
        0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
            0x0000...0x1fff => true,
            else => false,
        },
        0x7e, 0x7f => true,
        0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
            0x0000...0x1fff => true,
            else => false,
        },
        else => false,
    };
}

fn isIOaddress(address: u24) bool {
    return switch (@as(u8, @truncate(address >> 16))) {
        0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
            0x2100...0x43ff => blk: {
                break :blk switch (address & 0xffff) {
                    0x2100...0x21ff, 0x4300...0x437f, 0x420b, 0x420c => true,
                    else => false,
                };
            },
            else => false,
        },
        0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
            0x2100...0x43ff => blk: {
                break :blk switch (address & 0xffff) {
                    0x2100...0x21ff, 0x4300...0x437f, 0x420b, 0x420c => true,
                    else => false,
                };
            },
            else => false,
        },
        else => false,
    };
}

const Channel = struct {
    src_address: u16,
    transfer_size: u16,
    hdma_table_address: u16,
    src_bank: u8,
    dest_address: u8,
    dma_active: bool,
    dmap: DMAP,
    hdma_bank: u8,
    hdma_line_counter: u8,
    do_transfer: bool,
    hdma_finished: bool,
};

pub const DMA = struct {
    allocator: std.mem.Allocator,
    bus: Memory(u24, u8),
    openbus: *u8,

    channels: [8]Channel = [_]Channel{std.mem.zeroes(Channel)} ** 8,
    need_to_process: bool = false,
    hdma_pending: bool = false,
    hdma_init_pending: bool = false,
    dma_start_delay: bool = false,
    dma_pending: bool = false,
    hdma_channels: u8 = 0,

    // DMA UNUSEDx byte
    unused: [8]u8 = [_]u8{0xff} ** 8,

    dma_offset_counter: *u3,
    cycle_counter: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, bus: Memory(u24, u8), openbus: *u8, offset_counter: *u3) !*DMA {
        const instance = try allocator.create(DMA);
        instance.* = .{
            .allocator = allocator,
            .openbus = openbus,
            .dma_offset_counter = offset_counter,
            .bus = bus,
        };
        return instance;
    }

    pub fn deinit(self: *DMA) void {
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return switch (address) {
            @intFromEnum(IO.DMAP0),
            @intFromEnum(IO.DMAP1),
            @intFromEnum(IO.DMAP2),
            @intFromEnum(IO.DMAP3),
            @intFromEnum(IO.DMAP4),
            @intFromEnum(IO.DMAP5),
            @intFromEnum(IO.DMAP6),
            @intFromEnum(IO.DMAP7),
            => @as(u8, @bitCast(self.channels[(address & 0x70) >> 4].dmap)),

            @intFromEnum(IO.BBAD0),
            @intFromEnum(IO.BBAD1),
            @intFromEnum(IO.BBAD2),
            @intFromEnum(IO.BBAD3),
            @intFromEnum(IO.BBAD4),
            @intFromEnum(IO.BBAD5),
            @intFromEnum(IO.BBAD6),
            @intFromEnum(IO.BBAD7),
            => @intCast(self.channels[(address & 0x70) >> 4].dest_address),

            @intFromEnum(IO.A1T0L),
            @intFromEnum(IO.A1T1L),
            @intFromEnum(IO.A1T2L),
            @intFromEnum(IO.A1T3L),
            @intFromEnum(IO.A1T4L),
            @intFromEnum(IO.A1T5L),
            @intFromEnum(IO.A1T6L),
            @intFromEnum(IO.A1T7L),
            => @intCast(self.channels[(address & 0x70) >> 4].src_address & 0xff),

            @intFromEnum(IO.A1T0H),
            @intFromEnum(IO.A1T1H),
            @intFromEnum(IO.A1T2H),
            @intFromEnum(IO.A1T3H),
            @intFromEnum(IO.A1T4H),
            @intFromEnum(IO.A1T5H),
            @intFromEnum(IO.A1T6H),
            @intFromEnum(IO.A1T7H),
            => @intCast(self.channels[(address & 0x70) >> 4].src_address >> 8),

            @intFromEnum(IO.A1B0),
            @intFromEnum(IO.A1B1),
            @intFromEnum(IO.A1B2),
            @intFromEnum(IO.A1B3),
            @intFromEnum(IO.A1B4),
            @intFromEnum(IO.A1B5),
            @intFromEnum(IO.A1B6),
            @intFromEnum(IO.A1B7),
            => self.channels[(address & 0x70) >> 4].src_bank,

            @intFromEnum(IO.DAS0L),
            @intFromEnum(IO.DAS1L),
            @intFromEnum(IO.DAS2L),
            @intFromEnum(IO.DAS3L),
            @intFromEnum(IO.DAS4L),
            @intFromEnum(IO.DAS5L),
            @intFromEnum(IO.DAS6L),
            @intFromEnum(IO.DAS7L),
            => @intCast(self.channels[(address & 0x70) >> 4].transfer_size & 0xff),

            @intFromEnum(IO.DAS0H),
            @intFromEnum(IO.DAS1H),
            @intFromEnum(IO.DAS2H),
            @intFromEnum(IO.DAS3H),
            @intFromEnum(IO.DAS4H),
            @intFromEnum(IO.DAS5H),
            @intFromEnum(IO.DAS6H),
            @intFromEnum(IO.DAS7H),
            => @intCast(self.channels[(address & 0x70) >> 4].transfer_size >> 8),

            @intFromEnum(IO.DASB0),
            @intFromEnum(IO.DASB1),
            @intFromEnum(IO.DASB2),
            @intFromEnum(IO.DASB3),
            @intFromEnum(IO.DASB4),
            @intFromEnum(IO.DASB5),
            @intFromEnum(IO.DASB6),
            @intFromEnum(IO.DASB7),
            => self.channels[(address & 0x70) >> 4].hdma_bank,

            @intFromEnum(IO.A2A0L),
            @intFromEnum(IO.A2A1L),
            @intFromEnum(IO.A2A2L),
            @intFromEnum(IO.A2A3L),
            @intFromEnum(IO.A2A4L),
            @intFromEnum(IO.A2A5L),
            @intFromEnum(IO.A2A6L),
            @intFromEnum(IO.A2A7L),
            => @intCast(self.channels[(address & 0x70) >> 4].hdma_table_address & 0xff),

            @intFromEnum(IO.A2A0H),
            @intFromEnum(IO.A2A1H),
            @intFromEnum(IO.A2A2H),
            @intFromEnum(IO.A2A3H),
            @intFromEnum(IO.A2A4H),
            @intFromEnum(IO.A2A5H),
            @intFromEnum(IO.A2A6H),
            @intFromEnum(IO.A2A7H),
            => @intCast(self.channels[(address & 0x70) >> 4].hdma_table_address >> 8),

            @intFromEnum(IO.NLTR0),
            @intFromEnum(IO.NLTR1),
            @intFromEnum(IO.NLTR2),
            @intFromEnum(IO.NLTR3),
            @intFromEnum(IO.NLTR4),
            @intFromEnum(IO.NLTR5),
            @intFromEnum(IO.NLTR6),
            @intFromEnum(IO.NLTR7),
            => self.channels[(address & 0x70) >> 4].hdma_line_counter,

            0x430b, 0x430f => self.unused[0],
            0x431b, 0x431f => self.unused[1],
            0x432b, 0x432f => self.unused[2],
            0x433b, 0x433f => self.unused[3],
            0x434b, 0x434f => self.unused[4],
            0x435b, 0x435f => self.unused[5],
            0x436b, 0x436f => self.unused[6],
            0x437b, 0x437f => self.unused[7],
            else => 0,
        };
    }

    pub fn write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            @intFromEnum(IO.HDMAEN) => {
                self.hdma_channels = value;
            },

            @intFromEnum(IO.MDMAEN) => {
                for (0..8) |i| {
                    if ((value & (@as(u8, 1) << @as(u3, @intCast(i)))) > 0) {
                        self.channels[i].dma_active = true;
                    }
                }
                if (value > 0) {
                    self.dma_pending = true;
                    self.dma_start_delay = true;
                    self.updateNeedToProcessFlag();
                }
            },

            @intFromEnum(IO.DMAP0),
            @intFromEnum(IO.DMAP1),
            @intFromEnum(IO.DMAP2),
            @intFromEnum(IO.DMAP3),
            @intFromEnum(IO.DMAP4),
            @intFromEnum(IO.DMAP5),
            @intFromEnum(IO.DMAP6),
            @intFromEnum(IO.DMAP7),
            => self.channels[(address & 0x70) >> 4].dmap = @bitCast(value),

            @intFromEnum(IO.BBAD0),
            @intFromEnum(IO.BBAD1),
            @intFromEnum(IO.BBAD2),
            @intFromEnum(IO.BBAD3),
            @intFromEnum(IO.BBAD4),
            @intFromEnum(IO.BBAD5),
            @intFromEnum(IO.BBAD6),
            @intFromEnum(IO.BBAD7),
            => self.channels[(address & 0x70) >> 4].dest_address = value,

            @intFromEnum(IO.A1T0L),
            @intFromEnum(IO.A1T1L),
            @intFromEnum(IO.A1T2L),
            @intFromEnum(IO.A1T3L),
            @intFromEnum(IO.A1T4L),
            @intFromEnum(IO.A1T5L),
            @intFromEnum(IO.A1T6L),
            @intFromEnum(IO.A1T7L),
            => self.channels[(address & 0x70) >> 4].src_address = (self.channels[(address & 0x70) >> 4].src_address & 0xff00) | value,

            @intFromEnum(IO.A1T0H),
            @intFromEnum(IO.A1T1H),
            @intFromEnum(IO.A1T2H),
            @intFromEnum(IO.A1T3H),
            @intFromEnum(IO.A1T4H),
            @intFromEnum(IO.A1T5H),
            @intFromEnum(IO.A1T6H),
            @intFromEnum(IO.A1T7H),
            => self.channels[(address & 0x70) >> 4].src_address = (@as(u16, value) << 8) | (self.channels[(address & 0x70) >> 4].src_address & 0x00ff),

            @intFromEnum(IO.A1B0),
            @intFromEnum(IO.A1B1),
            @intFromEnum(IO.A1B2),
            @intFromEnum(IO.A1B3),
            @intFromEnum(IO.A1B4),
            @intFromEnum(IO.A1B5),
            @intFromEnum(IO.A1B6),
            @intFromEnum(IO.A1B7),
            => self.channels[(address & 0x70) >> 4].src_bank = value,

            @intFromEnum(IO.DAS0L),
            @intFromEnum(IO.DAS1L),
            @intFromEnum(IO.DAS2L),
            @intFromEnum(IO.DAS3L),
            @intFromEnum(IO.DAS4L),
            @intFromEnum(IO.DAS5L),
            @intFromEnum(IO.DAS6L),
            @intFromEnum(IO.DAS7L),
            => self.channels[(address & 0x70) >> 4].transfer_size = (self.channels[(address & 0x70) >> 4].transfer_size & 0xff00) | value,

            @intFromEnum(IO.DAS0H),
            @intFromEnum(IO.DAS1H),
            @intFromEnum(IO.DAS2H),
            @intFromEnum(IO.DAS3H),
            @intFromEnum(IO.DAS4H),
            @intFromEnum(IO.DAS5H),
            @intFromEnum(IO.DAS6H),
            @intFromEnum(IO.DAS7H),
            => self.channels[(address & 0x70) >> 4].transfer_size = (@as(u16, value) << 8) | (self.channels[(address & 0x70) >> 4].transfer_size & 0x00ff),

            @intFromEnum(IO.DASB0),
            @intFromEnum(IO.DASB1),
            @intFromEnum(IO.DASB2),
            @intFromEnum(IO.DASB3),
            @intFromEnum(IO.DASB4),
            @intFromEnum(IO.DASB5),
            @intFromEnum(IO.DASB6),
            @intFromEnum(IO.DASB7),
            => self.channels[(address & 0x70) >> 4].hdma_bank = value,

            @intFromEnum(IO.A2A0L),
            @intFromEnum(IO.A2A1L),
            @intFromEnum(IO.A2A2L),
            @intFromEnum(IO.A2A3L),
            @intFromEnum(IO.A2A4L),
            @intFromEnum(IO.A2A5L),
            @intFromEnum(IO.A2A6L),
            @intFromEnum(IO.A2A7L),
            => self.channels[(address & 0x70) >> 4].hdma_table_address = (self.channels[(address & 0x70) >> 4].hdma_table_address & 0xff00) | value,

            @intFromEnum(IO.A2A0H),
            @intFromEnum(IO.A2A1H),
            @intFromEnum(IO.A2A2H),
            @intFromEnum(IO.A2A3H),
            @intFromEnum(IO.A2A4H),
            @intFromEnum(IO.A2A5H),
            @intFromEnum(IO.A2A6H),
            @intFromEnum(IO.A2A7H),
            => self.channels[(address & 0x70) >> 4].hdma_table_address = (@as(u16, value) << 8) | (self.channels[(address & 0x70) >> 4].hdma_table_address & 0x00ff),

            @intFromEnum(IO.NLTR0),
            @intFromEnum(IO.NLTR1),
            @intFromEnum(IO.NLTR2),
            @intFromEnum(IO.NLTR3),
            @intFromEnum(IO.NLTR4),
            @intFromEnum(IO.NLTR5),
            @intFromEnum(IO.NLTR6),
            @intFromEnum(IO.NLTR7),
            => self.channels[(address & 0x70) >> 4].hdma_line_counter = value,

            0x430b, 0x430f => self.unused[0] = value,
            0x431b, 0x431f => self.unused[1] = value,
            0x432b, 0x432f => self.unused[2] = value,
            0x433b, 0x433f => self.unused[3] = value,
            0x434b, 0x434f => self.unused[4] = value,
            0x435b, 0x435f => self.unused[5] = value,
            0x436b, 0x436f => self.unused[6] = value,
            0x437b, 0x437f => self.unused[7] = value,
            else => {},
        }
    }

    fn transferByte(self: *DMA, a_bus: u24, b_bus: u8, direction: TransferDirection) void {
        const valid = !isIOaddress(a_bus) and (!isWRAMaddress(a_bus) or b_bus != 0x80);
        if (direction == .a2b) {
            if (valid) {
                self.bus.write(@as(u16, 0x2100) | b_bus, self.bus.read(a_bus));
            }
        } else {
            if (valid) {
                self.bus.write(a_bus, self.bus.read(@as(u16, 0x2100) | b_bus));
            } else {
                self.bus.write(a_bus, self.openbus.*);
            }
        }
        self.cycle_counter += 8;
    }

    fn dma(self: *DMA, channel: *Channel) void {
        if (!channel.dma_active) return;
        self.cycle_counter += 8;
        _ = self.processPendingTransfers();
        const pattern = PATTERN[channel.dmap.pattern][1..5];
        var i: usize = 0;
        while (true) {
            self.transferByte((@as(u24, channel.src_bank) << 16) | channel.src_address, channel.dest_address + pattern[i % 4], channel.dmap.direction);
            if (channel.dmap.adjust == .inc) {
                channel.src_address +%= 1;
            } else if (channel.dmap.adjust == .dec) {
                channel.src_address -%= 1;
            }
            channel.transfer_size -%= 1;
            i += 1;
            _ = self.processPendingTransfers();
            if (channel.transfer_size == 0 or !channel.dma_active) break;
        }
        channel.dma_active = false;
    }

    fn hdmaInit(self: *DMA) bool {
        self.hdma_init_pending = false;

        for (0..8) |i| {
            self.channels[i].hdma_finished = false;
            self.channels[i].do_transfer = false;
        }

        if (self.hdma_channels == 0) {
            self.updateNeedToProcessFlag();
            return false;
        }

        const need_sync = !self.hasActiveDmaChannel();
        if (need_sync) self.cycle_counter += @as(u8, 8) - self.dma_offset_counter.*;
        self.cycle_counter += 8;

        for (0..8) |i| {
            var channel = &self.channels[i];
            channel.do_transfer = true;
            if ((self.hdma_channels & (@as(u8, 1) << @as(u3, @intCast(i)))) > 0) {
                channel.hdma_table_address = channel.src_address;
                channel.dma_active = false;
                channel.hdma_line_counter = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
                self.cycle_counter += 8;
                channel.hdma_table_address +%= 1;
                if (channel.hdma_line_counter == 0) channel.hdma_finished = true;
                if (channel.dmap.indirect) {
                    const lsb = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
                    channel.hdma_table_address +%= 1;
                    self.cycle_counter += 8;
                    const msb = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
                    channel.hdma_table_address +%= 1;
                    self.cycle_counter += 8;
                    channel.transfer_size = (@as(u16, msb) << 8) | lsb;
                }
            }
        }

        if (need_sync) self.cycle_counter += 8;
        self.updateNeedToProcessFlag();
        return true;
    }

    fn hdmaTransfer(self: *DMA, channel: *Channel) void {
        const bytes = PATTERN[channel.dmap.pattern][0];
        const pattern = PATTERN[channel.dmap.pattern][1 .. bytes + 1];
        channel.dma_active = false;
        for (0..bytes) |i| {
            if (channel.dmap.indirect) {
                self.transferByte((@as(u24, channel.hdma_bank) << 16) | channel.transfer_size, channel.dest_address + pattern[i], channel.dmap.direction);
                channel.transfer_size +%= 1;
            } else {
                self.transferByte((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address, channel.dest_address + pattern[i], channel.dmap.direction);
                channel.hdma_table_address +%= 1;
            }
        }
    }

    fn hasActiveDmaChannel(self: *DMA) bool {
        for (0..8) |i| {
            if (self.channels[i].dma_active) return true;
        }
        return false;
    }

    fn processHdmaChannels(self: *DMA) bool {
        self.hdma_pending = false;

        if (self.hdma_channels == 0) {
            self.updateNeedToProcessFlag();
            return false;
        }

        const need_sync = !self.hasActiveDmaChannel();
        if (need_sync) self.cycle_counter += @as(u8, 8) - self.dma_offset_counter.*;
        self.cycle_counter += 8;

        for (0..8) |i| {
            var channel = &self.channels[i];
            if ((self.hdma_channels & (@as(u8, 1) << @as(u3, @intCast(i)))) == 0) continue;
            channel.dma_active = false;
            if (channel.hdma_finished) continue;
            if (channel.do_transfer) {
                self.hdmaTransfer(channel);
            }
        }

        for (0..8) |i| {
            var channel = &self.channels[i];
            if ((self.hdma_channels & (@as(u8, 1) << @as(u3, @intCast(i)))) == 0 or channel.hdma_finished) continue;
            channel.hdma_line_counter -%= 1;
            channel.do_transfer = (channel.hdma_line_counter & 0x80) != 0;
            const new_counter = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
            self.cycle_counter += 8;
            if ((channel.hdma_line_counter & 0x7f) == 0) {
                channel.hdma_line_counter = new_counter;
                channel.hdma_table_address +%= 1;
                if (channel.dmap.indirect) {
                    if (channel.hdma_line_counter == 0 and self.isLastActiveHdmaChannel(i)) {
                        const msb = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
                        channel.hdma_table_address +%= 1;
                        self.cycle_counter += 8;
                        channel.transfer_size = (@as(u16, msb) << 8);
                    } else {
                        const lsb = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
                        channel.hdma_table_address +%= 1;
                        self.cycle_counter += 8;
                        const msb = self.bus.read((@as(u24, channel.src_bank) << 16) | channel.hdma_table_address);
                        channel.hdma_table_address +%= 1;
                        self.cycle_counter += 8;
                        channel.transfer_size = (@as(u16, msb) << 8) | lsb;
                    }
                }

                if (channel.hdma_line_counter == 0) channel.hdma_finished = true;
                channel.do_transfer = true;
            }
        }

        if (need_sync) self.cycle_counter += 8;
        self.updateNeedToProcessFlag();
        return true;
    }

    fn isLastActiveHdmaChannel(self: *DMA, channel: usize) bool {
        for (channel + 1..8) |i| {
            if (((self.hdma_channels & (@as(u8, 1) << @as(u3, @intCast(i)))) > 0) and !self.channels[i].hdma_finished) {
                return false;
            }
        }
        return true;
    }

    fn updateNeedToProcessFlag(self: *DMA) void {
        self.need_to_process = self.hdma_pending or self.hdma_init_pending or self.dma_start_delay or self.dma_pending;
    }

    pub fn beginHdmaTransfer(self: *DMA) void {
        if (self.hdma_channels > 0) {
            self.hdma_pending = true;
            self.updateNeedToProcessFlag();
        }
    }

    pub fn beginHdmaInit(self: *DMA) void {
        self.hdma_init_pending = true;
        self.updateNeedToProcessFlag();
    }

    fn processPendingTransfers(self: *DMA) bool {
        if (!self.need_to_process) return false;
        if (self.dma_start_delay) {
            self.dma_start_delay = false;
            return false;
        }
        if (self.hdma_pending) {
            return self.processHdmaChannels();
        } else if (self.hdma_init_pending) {
            return self.hdmaInit();
        } else if (self.dma_pending) {
            self.dma_pending = false;
            self.cycle_counter += @as(u8, 8) - self.dma_offset_counter.*;
            self.cycle_counter += 8;
            _ = self.processPendingTransfers();
            for (0..8) |i| {
                if (self.channels[i].dma_active) {
                    self.dma(&self.channels[i]);
                }
            }
            self.cycle_counter += 8;
            self.updateNeedToProcessFlag();
            return true;
        }
        return false;
    }

    pub fn process(self: *DMA) void {
        self.cycle_counter -|= 1;
        if (self.cycle_counter > 0) return;
        _ = self.processPendingTransfers();
    }

    pub fn reset(self: *DMA) void {
        self.hdma_channels = 0;
        self.hdma_pending = false;
        self.hdma_init_pending = false;
        self.dma_start_delay = false;
        self.dma_pending = false;
        self.need_to_process = false;
        for (0..8) |i| {
            self.channels[i].dma_active = false;
            for (0..12) |j| {
                self.bus.write(@as(u24, @intCast(0x4300 + (i << 4) + j)), 0xff);
            }
        }
    }

    pub fn serialize(self: *const DMA, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "unused");
        c.mpack_start_bin(pack, @intCast(self.unused.len));
        c.mpack_write_bytes(pack, &self.unused, self.unused.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "channels");
        c.mpack_build_array(pack);
        for (0..8) |i| {
            c.mpack_build_map(pack);
            c.mpack_write_cstr(pack, "src_address");
            c.mpack_write_u16(pack, self.channels[i].src_address);
            c.mpack_write_cstr(pack, "transfer_size");
            c.mpack_write_u16(pack, self.channels[i].transfer_size);
            c.mpack_write_cstr(pack, "hdma_table_address");
            c.mpack_write_u16(pack, self.channels[i].hdma_table_address);
            c.mpack_write_cstr(pack, "src_bank");
            c.mpack_write_u8(pack, self.channels[i].src_bank);
            c.mpack_write_cstr(pack, "dest_address");
            c.mpack_write_u8(pack, self.channels[i].dest_address);
            c.mpack_write_cstr(pack, "dma_active");
            c.mpack_write_bool(pack, self.channels[i].dma_active);
            c.mpack_write_cstr(pack, "dmap");
            c.mpack_write_u8(pack, @as(u8, @bitCast(self.channels[i].dmap)));
            c.mpack_write_cstr(pack, "hdma_bank");
            c.mpack_write_u8(pack, self.channels[i].hdma_bank);
            c.mpack_write_cstr(pack, "hdma_line_counter");
            c.mpack_write_u8(pack, self.channels[i].hdma_line_counter);
            c.mpack_write_cstr(pack, "do_transfer");
            c.mpack_write_bool(pack, self.channels[i].do_transfer);
            c.mpack_write_cstr(pack, "hdma_finished");
            c.mpack_write_bool(pack, self.channels[i].hdma_finished);
            c.mpack_complete_map(pack);
        }
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "need_to_process");
        c.mpack_write_bool(pack, self.need_to_process);
        c.mpack_write_cstr(pack, "hdma_pending");
        c.mpack_write_bool(pack, self.hdma_pending);
        c.mpack_write_cstr(pack, "hdma_init_pending");
        c.mpack_write_bool(pack, self.hdma_init_pending);
        c.mpack_write_cstr(pack, "dma_start_delay");
        c.mpack_write_bool(pack, self.dma_start_delay);
        c.mpack_write_cstr(pack, "dma_pending");
        c.mpack_write_bool(pack, self.dma_pending);
        c.mpack_write_cstr(pack, "hdma_channels");
        c.mpack_write_u8(pack, self.hdma_channels);
        c.mpack_write_cstr(pack, "cycle_counter");
        c.mpack_write_u32(pack, self.cycle_counter);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *DMA, pack: c.mpack_node_t) void {
        @memset(&self.unused, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "unused"), &self.unused, self.unused.len);

        for (0..8) |i| {
            const channel = c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "channels"), i);
            self.channels[i].src_address = c.mpack_node_u16(c.mpack_node_map_cstr(channel, "src_address"));
            self.channels[i].transfer_size = c.mpack_node_u16(c.mpack_node_map_cstr(channel, "transfer_size"));
            self.channels[i].hdma_table_address = c.mpack_node_u16(c.mpack_node_map_cstr(channel, "hdma_table_address"));
            self.channels[i].src_bank = c.mpack_node_u8(c.mpack_node_map_cstr(channel, "src_bank"));
            self.channels[i].dest_address = c.mpack_node_u8(c.mpack_node_map_cstr(channel, "dest_address"));
            self.channels[i].dma_active = c.mpack_node_bool(c.mpack_node_map_cstr(channel, "dma_active"));
            self.channels[i].dmap = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(channel, "dmap")));
            self.channels[i].hdma_bank = c.mpack_node_u8(c.mpack_node_map_cstr(channel, "hdma_bank"));
            self.channels[i].hdma_line_counter = c.mpack_node_u8(c.mpack_node_map_cstr(channel, "hdma_line_counter"));
            self.channels[i].do_transfer = c.mpack_node_bool(c.mpack_node_map_cstr(channel, "do_transfer"));
            self.channels[i].hdma_finished = c.mpack_node_bool(c.mpack_node_map_cstr(channel, "hdma_finished"));
        }

        self.need_to_process = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "need_to_process"));
        self.hdma_pending = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "hdma_pending"));
        self.hdma_init_pending = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "hdma_init_pending"));
        self.dma_start_delay = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "dma_start_delay"));
        self.dma_pending = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "dma_pending"));
        self.hdma_channels = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "hdma_channels"));
        self.cycle_counter = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "cycle_counter"));
    }

    pub fn memory(self: *@This()) Memory(u24, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }
};

const TransferDirection = enum(u1) { a2b = 0, b2a };

const DMAP = packed struct {
    pattern: u3,
    adjust: enum(u2) { inc = 0, fixed = 1, dec = 2, fixed_2 = 3 },
    unused: u1,
    indirect: bool,
    direction: TransferDirection,
};
