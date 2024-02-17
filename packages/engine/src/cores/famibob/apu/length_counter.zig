pub const LengthCounter = struct {
    const lookup_table: []const u8 = &[_]u8{ 10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30 };

    new_halt_value: bool = false,
    enabled: bool = false,
    halt: bool = false,
    counter: u8 = 0,
    reload_value: u8 = 0,
    previous_value: u8 = 0,

    pub fn initLengthCounter(self: *LengthCounter, halt_flag: bool) void {
        self.new_halt_value = halt_flag;
    }

    pub fn loadLengthCounter(self: *LengthCounter, value: u8) void {
        if (self.enabled) {
            self.reload_value = lookup_table[value];
            self.previous_value = self.counter;
        }
    }

    pub fn reloadCounter(self: *LengthCounter) void {
        if (self.reload_value > 0) {
            if (self.counter == self.previous_value) {
                self.counter = self.reload_value;
            }
            self.reload_value = 0;
        }
        self.halt = self.new_halt_value;
    }

    pub fn tickLengthCounter(self: *LengthCounter) void {
        if (self.counter > 0 and !self.halt) {
            self.counter -= 1;
        }
    }

    pub fn getStatus(self: *LengthCounter) bool {
        return self.counter > 0;
    }

    pub fn setEnabled(self: *LengthCounter, is_enabled: bool) void {
        if (!is_enabled) self.counter = 0;
        self.enabled = is_enabled;
    }

    pub fn reset(self: *LengthCounter) void {
        self.enabled = false;
        self.halt = false;
        self.counter = 0;
        self.new_halt_value = false;
        self.reload_value = 0;
        self.previous_value = 0;
    }

    pub fn jsonStringify(self: *const LengthCounter, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("new_halt_value");
        try jw.write(self.new_halt_value);
        try jw.objectField("enabled");
        try jw.write(self.enabled);
        try jw.objectField("halt");
        try jw.write(self.halt);
        try jw.objectField("counter");
        try jw.write(self.counter);
        try jw.objectField("reload_value");
        try jw.write(self.reload_value);
        try jw.objectField("previous_value");
        try jw.write(self.previous_value);
        try jw.endObject();
    }
};
