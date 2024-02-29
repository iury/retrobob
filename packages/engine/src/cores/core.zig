const Self = @This();
const c = @import("../c.zig");

pub const State = enum { idle, playing, paused };
pub const Region = enum(u8) { ntsc = 1, pal = 2 };

ptr: *anyopaque,
vtable: *const VTable,
game_width: f32,
game_height: f32,
state: State = .idle,
region: Region = .ntsc,

pub const VTable = struct {
    render: *const fn (ctx: *anyopaque) void,
    getTexture: *const fn (ctx: *anyopaque) c.Texture,
    getShader: *const fn (ctx: *anyopaque, source: c.Rectangle, dest: c.Rectangle) ?c.Shader,
    resetGame: *const fn (ctx: *anyopaque) void,
    pauseGame: *const fn (ctx: *anyopaque) void,
    resumeGame: *const fn (ctx: *anyopaque) void,
    saveState: *const fn (ctx: *anyopaque, slot: u8) anyerror!void,
    loadState: *const fn (ctx: *anyopaque, slot: u8) anyerror!bool,
    changeRegion: *const fn (ctx: *anyopaque, region: Region) void,
    fillAudioBuffer: *const fn (ctx: *anyopaque, buffer: []f32) usize,
    persistBattery: *const fn (ctx: *anyopaque) void,
    deinit: *const fn (ctx: *anyopaque) void,
};

pub fn render(self: *Self) void {
    if (self.state == .playing) {
        self.vtable.render(self.ptr);
    }
}

pub fn getTexture(self: *Self) c.Texture {
    return self.vtable.getTexture(self.ptr);
}

pub fn getShader(self: *Self, source: c.Rectangle, dest: c.Rectangle) ?c.Shader {
    return self.vtable.getShader(self.ptr, source, dest);
}

pub fn resetGame(self: *Self) void {
    if (self.state != .idle) {
        self.vtable.resetGame(self.ptr);
    }
}

pub fn pauseGame(self: *Self) void {
    if (self.state == .playing) {
        self.state = .paused;
    }
}

pub fn resumeGame(self: *Self) void {
    if (self.state == .paused) {
        self.state = .playing;
    }
}

pub fn changeSlot(self: *Self, slot: u8) void {
    self.slot = slot;
}

pub fn saveState(self: *Self, slot: u8) !void {
    if (self.state != .idle) {
        try self.vtable.saveState(self.ptr, slot);
    }
}

pub fn loadState(self: *Self, slot: u8) !bool {
    if (self.state != .idle) {
        return try self.vtable.loadState(self.ptr, slot);
    }
    return true;
}

pub fn changeRegion(self: *Self, region: Region) void {
    if (self.state != .idle) {
        self.region = region;
        self.vtable.changeRegion(self.ptr, region);
    }
}

pub fn fillAudioBuffer(self: *Self, buffer: []f32) usize {
    return self.vtable.fillAudioBuffer(self.ptr, buffer);
}

pub fn persistBattery(self: *Self) void {
    if (self.state != .idle) {
        self.vtable.persistBattery(self.ptr);
    }
}

pub fn deinit(self: *Self) void {
    if (self.state != .idle) {
        self.state = .idle;
        self.vtable.deinit(self.ptr);
    }
}
