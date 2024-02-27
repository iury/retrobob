const std = @import("std");
const Region = @import("../core.zig").Region;
const Memory = @import("../../memory.zig").Memory;

const COLOR_PALETTE = [_]u32{
    0xFF666666, 0xFF882A00, 0xFFA71214, 0xFFA4003B,
    0xFF7E005C, 0xFF40006E, 0xFF00066C, 0xFF001D56,
    0xFF003533, 0xFF00480B, 0xFF005200, 0xFF084F00,
    0xFF4D4000, 0xFF000000, 0xFF000000, 0xFF000000,
    0xFFADADAD, 0xFFD95F15, 0xFFFF4042, 0xFFFE2775,
    0xFFCC1AA0, 0xFF7B1EB7, 0xFF2031B5, 0xFF004E99,
    0xFF006D6B, 0xFF008738, 0xFF00930C, 0xFF328F00,
    0xFF8D7C00, 0xFF000000, 0xFF000000, 0xFF000000,
    0xFFFFFEFF, 0xFFFFB064, 0xFFFF9092, 0xFFFF76C6,
    0xFFFF6AF3, 0xFFCC6EFE, 0xFF7081FE, 0xFF229EEA,
    0xFF00BEBC, 0xFF00D888, 0xFF30E45C, 0xFF82E045,
    0xFFDECD48, 0xFF4F4F4F, 0xFF000000, 0xFF000000,
    0xFFFFFEFF, 0xFFFFDFC0, 0xFFFFD2D3, 0xFFFFC8E8,
    0xFFFFC2FB, 0xFFEAC4FE, 0xFFC5CCFE, 0xFFA5D8F7,
    0xFF94E5E4, 0xFF96EFCF, 0xFFABF4BD, 0xFFCCF3B3,
    0xFFF2EBB5, 0xFFB8B8B8, 0xFF000000, 0xFF000000,
};

const PPUCTRL = struct {
    // base nametable address (00: 0x2000; 01: 0x2400; 10: 0x2800; 11: 0x2C00)
    nametable_select: u2 = 0,
    // VRAM address increment per CPU read/write of PPUDATA
    // (0: add 1, going across; 1: add 32, going down)
    increment_mode: bool = false,
    // sprite pattern table address for 8x8 sprites
    // (0: 0x0000; 1: 0x1000; ignored in 8x16 mode)
    sprite_select: bool = false,
    // background pattern table address (0: 0x0000; 1: 0x1000)
    background_select: bool = false,
    // large sprites (0: 8x8 pixels; 1: 8x16 pixels)
    large_sprites: bool = false,
    // PPU master/slave select
    is_master: bool = false,
    // generate an NMI at the start of vblank (0: off; 1: on)
    nmi: bool = false,
};

const PPUMASK = struct {
    // grayscale (0: normal color, 1: grayscale)
    grayscale: bool = false,
    // 1: show background in leftmost 8 pixels of screen, 0: hide
    leftmost_background: bool = false,
    // show sprites in leftmost 8 pixels of screen, 0: hide
    leftmost_sprites: bool = false,
    // show background
    show_background: bool = false,
    ///** show sprites
    show_sprites: bool = false,
    // emphasize red (green on PAL)
    intensify_red: bool = false,
    // emphasize green (red on PAL)
    intensify_green: bool = false,
    // emphasize blue
    intensify_blue: bool = false,
};

const PPUSCROLL = struct {
    // during rendering, specifies the starting coarse-x scroll for the next
    // scanline and the starting y scroll for the screen.
    // otherwise holds the scroll or address before transferring it to v */
    t: u16 = 0,
    // fine-x position of the current scroll, used during rendering alongside v */
    x: u8 = 0,
    // toggles on each write to either PPUSCROLL or PPUADDR,
    // indicating whether this is the first or second write.
    // clears on reads of PPUSTATUS */
    w: bool = false,
};

const PPUSTATUS = struct {
    // vblank has started (0: not in vblank; 1: in vblank)
    // set at dot 1 of line 241; cleared after reading $2002
    // and at dot 1 of the prerender line. */
    vblank: bool = false,
    // sprite 0 hit. set when a nonzero pixel of sprite 0 overlaps a
    // nonzero background pixel; cleared at dot 1 of the prerender line. */
    sprite0_hit: bool = false,
    // sprite overflow. set whenever more than eight sprites appear on
    // a scanline during sprite evaluation. cleared at dot 1 of the
    // prerender line. */
    overflow: bool = false,
};

const SpriteTile = struct {
    sprite_x: u8 = 0,
    pattern: [2]u8 = .{ 0, 0 },
    palette_offset: u8 = 0,
    bg_priority: bool = false,
    flip_h: bool = false,
};

pub const PPU = struct {
    allocator: std.mem.Allocator,
    region: Region = .ntsc,
    mapper: Memory(u16, u8),

    // PPUCTRL ($2000)
    ctrl: PPUCTRL = .{},

    // // PPUMASK ($2001)
    mask: PPUMASK = .{},

    // PPUSTATUS ($2002)
    status: PPUSTATUS = .{},

    // OAMADDR ($2003)
    oamaddr: u8 = 0,

    // OAMDATA ($2004)
    oamdata: [256]u8 = [_]u8{0} ** 256,

    // PPUSCROLL ($2005)
    scroll: PPUSCROLL = .{},

    // PPUADDR ($2006)
    ppuaddr: u16 = 0,

    // PPUDATA ($2007)
    ppudata: u8 = 0,

    // background
    palette: [32]u8 = [_]u8{0} ** 32,
    bgtile: [2]u8 = .{ 0, 0 },
    bgattr: [2]u8 = .{ 0, 0 },
    pattern: [2]u16 = .{ 0, 0 },
    bgtileaddr: u16 = 0,
    bgnextattr: u8 = 0,

    // sprite
    secondary_oamdata: [256]u8 = [_]u8{0} ** 256,
    secondary_oamaddr: u8 = 0,
    oambuffer: u8 = 0,
    sprite_cnt: u8 = 0,
    sprite_idx: u8 = 0,
    sprite0_visible: bool = false,
    sprite_tiles: [8]SpriteTile = [_]SpriteTile{.{}} ** 8,
    has_sprite: [257]bool = [_]bool{false} ** 257,

    // sprite evaluation
    sprite0_added: bool = false,
    sprite_in_range: bool = false,
    copy_finished: bool = false,
    overflow_cnt: u8 = 0,
    sprite_addr_h: u8 = 0,
    sprite_addr_l: u8 = 0,

    openbus: u8 = 0,
    odd_frame: bool = false,
    buffer: u8 = 0,
    dot: u16 = 340,
    scanline: i32 = -1,
    vblank_line: u16 = 241,
    prerender_line: u16 = 261,
    rendering: bool = false,
    nmi_requested: bool = false,
    oam_dma: ?u16 = null,
    booting: ?u32 = 0,

    framebuf: []u32,

    pub fn init(allocator: std.mem.Allocator, mapper: Memory(u16, u8)) !*PPU {
        const instance = try allocator.create(PPU);
        instance.* = .{
            .allocator = allocator,
            .mapper = mapper,
            .framebuf = try allocator.alloc(u32, 61440),
        };
        return instance;
    }

    pub fn deinit(self: *PPU) void {
        self.allocator.free(self.framebuf);
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var openbus_mask: u8 = 0xff;
        var result: u8 = 0;

        if (address == 0x2002) {
            // PPUSTATUS
            openbus_mask = 0x1f;
            self.scroll.w = false;

            result =
                (if (self.status.vblank) @as(u8, 0x80) else 0) |
                (if (self.status.sprite0_hit) @as(u8, 0x40) else 0) |
                (if (self.status.overflow) @as(u8, 0x20) else 0);

            self.status.vblank = false;
            self.nmi_requested = false;
        } else if (address == 0x2004) {
            // OAMDATA
            openbus_mask = 0;

            if (self.rendering and self.scanline < 240) {
                if (self.dot >= 257 and self.dot <= 320) {
                    var step: u8 = @intCast((self.dot - 257) % 8);
                    if (step > 3) step = 3;
                    self.secondary_oamaddr = @as(u8, @intCast(self.dot - 257)) / 8 * 4 + step;
                    self.oambuffer = self.secondary_oamdata[self.secondary_oamaddr];
                }

                result = self.oambuffer;
            } else {
                result = self.oamdata[self.oamaddr];
            }
        } else if (address == 0x2007) {
            // PPUDATA
            if (self.booting != null) return 0;

            result = self.buffer;
            openbus_mask = 0;

            // put PPUDATA in the buffer for the next read
            self.buffer = self.mapper.read(self.ppuaddr & 0x3fff);

            if ((self.ppuaddr & 0x3fff) >= 0x3f00) {
                var addr = self.ppuaddr & 0x1f;
                if (addr == 0x10 or addr == 0x14 or addr == 0x18 or addr == 0x1c) addr &= ~@as(u8, 0x10);
                result = self.palette[addr];
                if (self.mask.grayscale) result &= 0x30;
                openbus_mask = 0xc0;
            }

            self.incrementAddr();
        }

        self.openbus = result | (self.openbus & openbus_mask);
        return self.openbus;
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (address != 0x4014) {
            self.openbus = value;
        }

        if (address == 0x2000) {
            // PPUCTRL
            if (self.booting != null) return;

            const prev_nmi = self.ctrl.nmi;

            self.ctrl = .{
                .nametable_select = @truncate(value & 0b11),
                .increment_mode = (value & 0x4) > 0,
                .sprite_select = (value & 0x8) > 0,
                .background_select = (value & 0x10) > 0,
                .large_sprites = (value & 0x20) > 0,
                .is_master = (value & 0x40) > 0,
                .nmi = (value & 0x80) > 0,
            };

            if (!self.ctrl.nmi) {
                self.nmi_requested = false;
            } else if (self.status.vblank and !prev_nmi and self.ctrl.nmi) {
                self.nmi_requested = true;
            }

            // t: ...GH.. ........ <- d: ......GH
            self.scroll.t = (self.scroll.t & ~@as(u16, 0xc00)) | (@as(u16, value & 0b11) << 10);
        } else if (address == 0x2001) {
            // PPUMASK
            if (self.booting != null) return;

            self.mask = .{
                .grayscale = (value & 0x1) > 0,
                .leftmost_background = (value & 0x2) > 0,
                .leftmost_sprites = (value & 0x4) > 0,
                .show_background = (value & 0x8) > 0,
                .show_sprites = (value & 0x10) > 0,
                .intensify_red = (value & 0x20) > 0,
                .intensify_green = (value & 0x40) > 0,
                .intensify_blue = (value & 0x80) > 0,
            };

            if (self.region == .pal) {
                // it is swapped in PAL
                const v = self.mask.intensify_red;
                self.mask.intensify_red = self.mask.intensify_green;
                self.mask.intensify_green = v;
            }

            self.rendering = self.mask.show_background or self.mask.show_sprites;
        } else if (address == 0x2003) {
            // OAMADDR
            self.oamaddr = value;
        } else if (address == 0x2004) {
            // OAMDATA
            var v = value;
            // OAM byte 2: bits 2, 3 and 4 are unimplemented
            if ((self.oamaddr & 3) == 2) v &= 0xe3;
            self.oamdata[self.oamaddr] = v;
            self.oamaddr +%= 1;
        } else if (address == 0x2005) {
            // PPUSCROLL
            if (self.booting != null) return;

            if (!self.scroll.w) {
                // t: ....... ...ABCDE <- d: ABCDE...
                // x:              FGH <- d: .....FGH
                // w:                  <- 1
                self.scroll.t = (self.scroll.t & ~@as(u16, 0x1F)) | (value >> 3);
                self.scroll.x = value & 0x7;
                self.scroll.w = true;
            } else {
                // t: FGH..AB CDE..... <- d: ABCDEFGH
                // w:                  <- 0
                self.scroll.t = (self.scroll.t & ~@as(u16, 0x73E0)) | (@as(u16, value & 0xF8) << 2) | (@as(u16, value & 7) << 12);
                self.scroll.w = false;
            }
        } else if (address == 0x2006) {
            // PPUADDR
            if (self.booting != null) return;

            if (!self.scroll.w) {
                // t: 0CDEFGH ........ <- d: ..CDEFGH (bit 14 is cleared)
                // w:                  <- 1
                self.scroll.t = (self.scroll.t & ~@as(u16, 0xFF00)) | (@as(u16, (value & 0x3F)) << 8);
                self.scroll.w = true;
            } else {
                // t: ....... ABCDEFGH <- d: ABCDEFGH
                // v: <...all bits...> <- t: <...all bits...>
                // w:                  <- 0
                self.scroll.t = (self.scroll.t & ~@as(u16, 0xFF)) | value;
                self.ppuaddr = self.scroll.t;
                self.scroll.w = false;
                if (self.scanline >= 240 or !self.rendering) {
                    _ = self.mapper.read(self.ppuaddr & 0x3fff);
                }
            }
        } else if (address == 0x2007) {
            // PPUDATA
            if ((self.ppuaddr & 0x3fff) >= 0x3f00) {
                // palette starts at 0x3F00 and it is mirrored every 0x20 bytes
                // addresses 3F10/3F14/3F18/3F1C are mirrors of 3F00/3F04/3F08/3F0C
                const addr = self.ppuaddr & 0x1f;
                const v = value & 0x3f;
                if (addr == 0x00 or addr == 0x10) {
                    self.palette[0x00] = v;
                    self.palette[0x10] = v;
                } else if (addr == 0x04 or addr == 0x14) {
                    self.palette[0x04] = v;
                    self.palette[0x14] = v;
                } else if (addr == 0x08 or addr == 0x18) {
                    self.palette[0x08] = v;
                    self.palette[0x18] = v;
                } else if (addr == 0x0c or addr == 0x1c) {
                    self.palette[0x0c] = v;
                    self.palette[0x1c] = v;
                } else {
                    self.palette[addr] = v;
                }
            } else {
                self.mapper.write(self.ppuaddr & 0x3fff, value);
            }

            self.incrementAddr();
        } else if (address == 0x4014) {
            // OAMDMA
            self.oam_dma = value;
        }
    }

    fn incrementAddr(self: *PPU) void {
        // PPUCTRL.increment_mode says how much the address will increment, by 1 or 32
        self.ppuaddr = (self.ppuaddr +% @as(u16, if (self.ctrl.increment_mode) 0x20 else 1)) & 0x7fff;
        _ = self.mapper.read(self.ppuaddr & 0x3fff);
    }

    fn incrementX(self: *PPU) void {
        if ((self.ppuaddr & 0x1f) == 0x1f) {
            // switch horizontal nametable
            self.ppuaddr = (self.ppuaddr & ~@as(u16, 0x1f)) ^ 0x0400;
        } else {
            self.ppuaddr += 1;
        }
    }

    fn incrementY(self: *PPU) void {
        if ((self.ppuaddr & 0x7000) != 0x7000) {
            self.ppuaddr += @as(u16, 0x1000);
        } else {
            self.ppuaddr &= ~@as(u16, 0x7000);
            var y: u16 = (self.ppuaddr & 0x03e0) >> 5;
            if (y == 29) {
                y = 0;
                // switch vertical nametable
                self.ppuaddr ^= @as(u16, 0x0800);
            } else if (y == 31) {
                y = 0;
            } else {
                y += 1;
            }
            self.ppuaddr = (self.ppuaddr & ~@as(u16, 0x03e0)) | (y << 5);
        }
    }

    fn loadTile(self: *PPU) void {
        if (self.rendering) {
            if (self.dot % 8 == 1) {
                const nmaddr = 0x2000 | (self.ppuaddr & 0x0fff);
                const idx = @as(u16, self.mapper.read(nmaddr));
                self.bgtileaddr = (idx << 4) | (self.ppuaddr >> 12) | @as(u16, if (self.ctrl.background_select) 0x1000 else 0);
                self.pattern[0] |= self.bgtile[0];
                self.pattern[1] |= self.bgtile[1];
                self.bgattr[0] = self.bgattr[1];
                self.bgattr[1] = self.bgnextattr;
            }

            if (self.dot % 8 == 3) {
                const attr = 0x23C0 | (self.ppuaddr & 0x0C00) | ((self.ppuaddr >> 4) & 0x38) | ((self.ppuaddr >> 2) & 0x07);
                const shift = @as(u3, @truncate((self.ppuaddr >> 4) & 0x04)) | @as(u3, @truncate(self.ppuaddr & 0x02));
                self.bgnextattr = ((self.mapper.read(attr) >> shift) & 0x3) << 2;
            }

            if (self.dot % 8 == 5) {
                self.bgtile[0] = self.mapper.read(self.bgtileaddr);
            }

            if (self.dot % 8 == 7) {
                self.bgtile[1] = self.mapper.read(self.bgtileaddr +% 8);
            }
        }
    }

    fn loadSprite(self: *PPU, y: u8, tile: u8, attr: u8, x: u8) void {
        if (self.sprite_idx < self.sprite_cnt and y < 240) {
            const offset: u8 = blk: {
                if ((attr & 0x80) == 0x80) {
                    const large_sprites: i32 = @as(i32, if (self.ctrl.large_sprites) 15 else 7);
                    break :blk @truncate(@as(u32, @bitCast((large_sprites - (self.scanline - @as(i32, @intCast(y)))))));
                } else {
                    break :blk @truncate(@as(u32, @bitCast(self.scanline - @as(i32, @intCast(y)))));
                }
            };

            const tileaddr: u16 = blk: {
                if (self.ctrl.large_sprites) {
                    break :blk (@as(u16, if (tile & 1 == 1) 0x1000 else 0) | (@as(u16, tile & 0xfe) << 4)) + @as(u16, if (offset >= 8) offset + 8 else offset);
                } else {
                    break :blk ((@as(u16, tile) << 4) | @as(u16, if (self.ctrl.sprite_select) 0x1000 else 0)) + offset;
                }
            };

            self.sprite_tiles[self.sprite_idx] = .{
                .sprite_x = x,
                .pattern = [_]u8{ self.mapper.read(tileaddr), self.mapper.read(tileaddr + 8) },
                .palette_offset = ((attr & 0x03) << 2) | 0x10,
                .bg_priority = (attr & 0x20) == 0x20,
                .flip_h = (attr & 0x40) == 0x40,
            };

            if (self.scanline >= 0) {
                for (0..8) |i| {
                    if (@as(u16, x) + i + 1 < 257) {
                        self.has_sprite[@as(u16, x) + i + 1] = true;
                    }
                }
            }
        } else {
            const tileaddr = blk: {
                if (self.ctrl.large_sprites) {
                    break :blk @as(u16, 0x1fe0);
                } else {
                    break :blk @as(u16, if (self.ctrl.sprite_select) 0x1ff0 else 0x0ff0);
                }
            };

            _ = self.mapper.read(tileaddr);
            _ = self.mapper.read(tileaddr + 8);
        }

        self.sprite_idx += 1;
    }

    fn spriteEvaluation(self: *PPU) void {
        if (self.rendering) {
            if (self.dot < 65) {
                self.oambuffer = 0xff;
                self.secondary_oamdata[(self.dot - 1) >> 1] = 0xff;
            } else {
                if (self.dot == 65) {
                    self.sprite0_added = false;
                    self.sprite_in_range = false;
                    self.secondary_oamaddr = 0;
                    self.overflow_cnt = 0;
                    self.copy_finished = false;
                    self.sprite_addr_h = (self.oamaddr >> 2) & 0x3f;
                    self.sprite_addr_l = self.oamaddr & 0x03;
                } else if (self.dot == 256) {
                    self.sprite0_visible = self.sprite0_added;
                    self.sprite_cnt = self.secondary_oamaddr >> 2;
                }

                if (self.dot % 2 == 1) {
                    self.oambuffer = self.oamdata[self.oamaddr];
                } else {
                    if (self.copy_finished) {
                        self.sprite_addr_h = (self.sprite_addr_h + 1) & 0x3f;
                        if (self.secondary_oamaddr >= 0x20) {
                            self.oambuffer = self.secondary_oamdata[self.secondary_oamaddr & 0x1f];
                        }
                    } else {
                        if (!self.sprite_in_range and (self.scanline >= self.oambuffer) and (self.scanline < self.oambuffer + @as(usize, if (self.ctrl.large_sprites) 16 else 8))) {
                            self.sprite_in_range = true;
                        }

                        if (self.secondary_oamaddr < 0x20) {
                            self.secondary_oamdata[self.secondary_oamaddr] = self.oambuffer;

                            if (self.sprite_in_range) {
                                self.sprite_addr_l += 1;
                                self.secondary_oamaddr += 1;

                                if (self.sprite_addr_h == 0) {
                                    self.sprite0_added = true;
                                }

                                if ((self.secondary_oamaddr & 0x03) == 0) {
                                    self.sprite_in_range = false;
                                    self.sprite_addr_l = 0;
                                    self.sprite_addr_h = (self.sprite_addr_h + 1) & 0x3f;
                                    if (self.sprite_addr_h == 0) {
                                        self.copy_finished = true;
                                    }
                                }
                            } else {
                                self.sprite_addr_h = (self.sprite_addr_h + 1) & 0x3f;
                                if (self.sprite_addr_h == 0) {
                                    self.copy_finished = true;
                                }
                            }
                        } else {
                            self.oambuffer = self.secondary_oamdata[self.secondary_oamaddr & 0x1f];

                            if (self.sprite_in_range) {
                                self.status.overflow = true;
                                self.sprite_addr_l += 1;
                                if (self.sprite_addr_l == 4) {
                                    self.sprite_addr_h = (self.sprite_addr_h + 1) & 0x3f;
                                    self.sprite_addr_l = 0;
                                }

                                if (self.overflow_cnt == 0) {
                                    self.overflow_cnt = 3;
                                } else if (self.overflow_cnt > 0) {
                                    self.overflow_cnt -= 1;
                                    if (self.overflow_cnt == 0) {
                                        self.copy_finished = true;
                                        self.sprite_addr_l = 0;
                                    }
                                }
                            } else {
                                self.sprite_addr_h = (self.sprite_addr_h + 1) & 0x3f;
                                self.sprite_addr_l = (self.sprite_addr_l + 1) & 0x03;

                                if (self.sprite_addr_h == 0) {
                                    self.copy_finished = true;
                                }
                            }
                        }
                    }
                    self.oamaddr = @as(u8, self.sprite_addr_l & 0x03) | (@as(u8, self.sprite_addr_h) << 2);
                }
            }
        }
    }

    fn getColor(self: *PPU) u8 {
        if (!self.rendering) return 0;

        const offset: u3 = @truncate(self.scroll.x);
        var bg_color: u2 = 0;

        const bg_visible = self.mask.show_background and (self.dot > 8 or self.mask.leftmost_background);
        const sprite_visible = self.mask.show_sprites and (self.dot > 8 or self.mask.leftmost_sprites);

        if (bg_visible) {
            bg_color = @truncate(((@as(u16, self.pattern[0] << offset) & 0x8000) >> 15) | ((@as(u16, self.pattern[1] << offset) & 0x8000) >> 14));
        }

        if (sprite_visible and self.has_sprite[self.dot]) {
            for (0..self.sprite_cnt) |i| {
                const sprite = &self.sprite_tiles[i];
                const expected_shift: i16 = @as(i16, @intCast(self.dot)) - @as(i16, @intCast(sprite.sprite_x)) - 1;
                if (expected_shift >= 0 and expected_shift < 8) {
                    const shift: u3 = @truncate(@as(u16, @intCast(expected_shift)));
                    var sprite_color: u2 = 0;
                    if (sprite.flip_h) {
                        sprite_color = @truncate(((sprite.pattern[0] >> shift) & 0x01) | (((sprite.pattern[1] >> shift) & 0x01) << 1));
                    } else {
                        sprite_color = @truncate((((sprite.pattern[0] << shift) & 0x80) >> 7) | (((sprite.pattern[1] << shift) & 0x80) >> 6));
                    }

                    if (sprite_color != 0) {
                        if (i == 0 and bg_color != 0 and self.sprite0_visible and self.dot != 256 and self.mask.show_background and !self.status.sprite0_hit) {
                            self.status.sprite0_hit = true;
                        }

                        if ((bg_color == 0 or !sprite.bg_priority)) {
                            return sprite.palette_offset + sprite_color;
                        }
                        break;
                    }
                }
            }
        }

        return (if (offset + ((self.dot - 1) % 8) < 8) self.bgattr[0] else self.bgattr[1]) + bg_color;
    }

    fn render(self: *PPU) void {
        var color: u8 = self.getColor();
        if (color & 0x3 == 0) color = 0;
        color = self.palette[color & 0x1f];
        if (self.mask.grayscale) color &= 0x30;
        var rgb_color = COLOR_PALETTE[color];

        if ((self.mask.intensify_red or self.mask.intensify_green or self.mask.intensify_blue) and (color & 0xf) <= 0xd) {
            var red: f32 = 1.0;
            var green: f32 = 1.0;
            var blue: f32 = 1.0;

            if (self.mask.intensify_red) {
                green *= 0.84;
                blue *= 0.84;
            }

            if (self.mask.intensify_green) {
                red *= 0.84;
                blue *= 0.84;
            }

            if (self.mask.intensify_blue) {
                red *= 0.84;
                green *= 0.84;
            }

            rgb_color = 0xff000000 //
            | (@as(u32, ((@min(@as(u32, 0xff), @as(u32, @intFromFloat(@as(f32, @floatFromInt((rgb_color & 0xff0000) >> 16)) * blue)))))) << 16) //
            | (@as(u32, ((@min(@as(u32, 0xff), @as(u32, @intFromFloat(@as(f32, @floatFromInt((rgb_color & 0xff00) >> 8)) * green)))))) << 8) //
            | (@as(u32, ((@min(@as(u32, 0xff), @as(u32, @intFromFloat(@as(f32, @floatFromInt(rgb_color & 0xff)) * red)))))));
        }

        self.framebuf[@as(u32, @bitCast(@as(i32, @truncate(self.scanline * 256 + self.dot - 1))))] = rgb_color;
    }

    fn run(self: *PPU) void {
        if (self.dot <= 256) {
            self.loadTile();

            if (self.rendering and (self.dot % 8) == 0) {
                self.incrementX();
                if (self.dot == 256) {
                    self.incrementY();
                }
            }

            if (self.scanline >= 0) {
                self.render();
                self.pattern[0] <<= 1;
                self.pattern[1] <<= 1;
                self.spriteEvaluation();
            } else if (self.dot < 9) {
                if (self.dot == 1) {
                    self.status.vblank = false;
                    self.nmi_requested = false;
                }
                if (self.rendering and self.oamaddr >= 0x08) {
                    self.oamdata[self.dot - 1] = self.oamdata[(self.oamaddr & 0xf8) + self.dot - 1];
                }
            }
        } else if (self.dot >= 257 and self.dot <= 320) {
            if (self.dot == 257) {
                self.sprite_idx = 0;
                @memset(self.has_sprite[0..], false);
                if (self.rendering) {
                    // v: ....A.. ...BCDEF <- t: ....A.. ...BCDEF
                    self.ppuaddr = (self.ppuaddr & ~@as(u16, 0x41f)) | (self.scroll.t & 0x41f);
                }
            }

            if (self.rendering) {
                self.oamaddr = 0;

                switch ((self.dot - 257) % 8) {
                    0 => {
                        _ = self.mapper.read(0x2000 | (self.ppuaddr & 0x0fff));
                    },
                    2 => {
                        _ = self.mapper.read(0x23C0 | (self.ppuaddr & 0x0c00) | ((self.ppuaddr >> 4) & 0x38) | ((self.ppuaddr >> 2) & 0x07));
                    },
                    4 => {
                        const sprite_addr = self.sprite_idx * 4;
                        self.loadSprite(
                            self.secondary_oamdata[sprite_addr],
                            self.secondary_oamdata[sprite_addr + 1],
                            self.secondary_oamdata[sprite_addr + 2],
                            self.secondary_oamdata[sprite_addr + 3],
                        );
                    },
                    else => {},
                }

                if (self.scanline == -1 and self.dot >= 280 and self.dot <= 304) {
                    // v: GHIA.BC DEF..... <- t: GHIA.BC DEF.....
                    self.ppuaddr = (self.ppuaddr & ~@as(u16, 0x7be0)) | (self.scroll.t & 0x7be0);
                }
            }
        } else if (self.dot >= 321 and self.dot <= 336) {
            self.loadTile();

            if (self.dot == 321) {
                if (self.rendering) {
                    self.oambuffer = self.secondary_oamdata[0];
                }
            } else if (self.rendering and (self.dot == 328 or self.dot == 336)) {
                self.pattern[0] <<= 8;
                self.pattern[1] <<= 8;
                self.incrementX();
            }
        } else if (self.dot == 337 or self.dot == 339) {
            if (self.rendering) {
                self.bgtileaddr = self.mapper.read(0x2000 | (self.ppuaddr & 0x0fff));
                if (self.dot == 339 and self.region == .ntsc and self.odd_frame and self.scanline == -1) {
                    self.dot = 340;
                }
            }
        }
    }

    pub fn setRegion(self: *PPU, region: Region) void {
        self.region = region;
        self.vblank_line = if (region == .ntsc) 241 else 291;
        self.prerender_line = if (region == .ntsc) 261 else 311;
    }

    pub fn process(self: *PPU) void {
        self.dot += 1;
        if (self.dot == 341) {
            self.dot = 0;
            self.scanline += 1;
            if (self.scanline == self.prerender_line) {
                self.scanline = -1;
                self.sprite_cnt = 0;
                self.odd_frame = !self.odd_frame;
            }
        }

        if (self.booting) |*b| {
            // hardware warm up cycles
            if (b.* == (if (self.region == .ntsc) @as(u32, 88974) else @as(u32, 106022))) {
                self.booting = null;
            } else {
                b.* +%= 1;
            }
        } else {
            if (self.scanline == -1 and self.dot == 0) {
                self.status.sprite0_hit = false;
                self.status.overflow = false;
            }

            if (self.scanline == 240 and self.dot == 0) {
                _ = self.mapper.read(self.ppuaddr & 0x3fff);
            }

            if (self.scanline == self.vblank_line and self.dot == 1) {
                self.status.vblank = true;
                if (self.ctrl.nmi) {
                    self.nmi_requested = true;
                }
            }

            if (self.dot > 0 and self.scanline < 240) {
                self.run();
            }
        }
    }

    pub fn reset(self: *PPU) void {
        self.ctrl = .{};
        self.mask = .{};
        self.status = .{};
        self.scroll = .{};
        self.dot = 340;
        self.scanline = -1;
        self.nmi_requested = false;
        self.oam_dma = null;
        self.rendering = false;
        self.booting = 0;
    }

    pub fn memory(self: *PPU) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }

    pub fn jsonStringify(self: *const PPU, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("ctrl");
        try jw.write(self.ctrl);
        try jw.objectField("mask");
        try jw.write(self.mask);
        try jw.objectField("status");
        try jw.write(self.status);
        try jw.objectField("oamaddr");
        try jw.write(self.oamaddr);
        try jw.objectField("oamdata");
        try jw.write(self.oamdata);
        try jw.objectField("scroll");
        try jw.write(self.scroll);
        try jw.objectField("ppuaddr");
        try jw.write(self.ppuaddr);
        try jw.objectField("ppudata");
        try jw.write(self.ppudata);
        try jw.objectField("palette");
        try jw.write(self.palette);
        try jw.objectField("bgtile");
        try jw.write(self.bgtile);
        try jw.objectField("bgattr");
        try jw.write(self.bgattr);
        try jw.objectField("pattern");
        try jw.write(self.pattern);
        try jw.objectField("bgtileaddr");
        try jw.write(self.bgtileaddr);
        try jw.objectField("bgnextattr");
        try jw.write(self.bgnextattr);
        try jw.objectField("secondary_oamdata");
        try jw.write(self.secondary_oamdata);
        try jw.objectField("secondary_oamaddr");
        try jw.write(self.secondary_oamaddr);
        try jw.objectField("oambuffer");
        try jw.write(self.oambuffer);
        try jw.objectField("sprite_cnt");
        try jw.write(self.sprite_cnt);
        try jw.objectField("sprite_idx");
        try jw.write(self.sprite_idx);
        try jw.objectField("sprite0_visible");
        try jw.write(self.sprite0_visible);
        try jw.objectField("sprite_tiles");
        try jw.write(self.sprite_tiles);
        try jw.objectField("has_sprite");
        try jw.write(self.has_sprite);
        try jw.objectField("sprite0_added");
        try jw.write(self.sprite0_added);
        try jw.objectField("sprite_in_range");
        try jw.write(self.sprite_in_range);
        try jw.objectField("copy_finished");
        try jw.write(self.copy_finished);
        try jw.objectField("overflow_cnt");
        try jw.write(self.overflow_cnt);
        try jw.objectField("sprite_addr_h");
        try jw.write(self.sprite_addr_h);
        try jw.objectField("sprite_addr_l");
        try jw.write(self.sprite_addr_l);
        try jw.objectField("openbus");
        try jw.write(self.openbus);
        try jw.objectField("odd_frame");
        try jw.write(self.odd_frame);
        try jw.objectField("buffer");
        try jw.write(self.buffer);
        try jw.objectField("dot");
        try jw.write(self.dot);
        try jw.objectField("scanline");
        try jw.write(self.scanline);
        try jw.objectField("vblank_line");
        try jw.write(self.vblank_line);
        try jw.objectField("prerender_line");
        try jw.write(self.prerender_line);
        try jw.objectField("rendering");
        try jw.write(self.rendering);
        try jw.objectField("nmi_requested");
        try jw.write(self.nmi_requested);
        try jw.objectField("oam_dma");
        try jw.write(self.oam_dma);
        try jw.objectField("booting");
        try jw.write(self.booting);
        try jw.endObject();
    }
};
