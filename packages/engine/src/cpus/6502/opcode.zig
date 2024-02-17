const std = @import("std");
const cpu = @import("cpu.zig");
const CPU = cpu.CPU;
const CPUCycle = cpu.CPUCycle;

fn nop(self: *CPU, addressing: Addressing) void {
    _ = self;
    _ = addressing;
}

fn hlt(self: *CPU, addressing: Addressing) void {
    _ = addressing;
    self.cycle_counter = 2;
    self.next_cycle = .read;
}

const adc = @import("instructions/adc.zig").adc;
const @"and" = @import("instructions/and.zig").@"and";
const asl = @import("instructions/asl.zig").asl;
const bcc = @import("instructions/bcc.zig").bcc;
const bcs = @import("instructions/bcs.zig").bcs;
const beq = @import("instructions/beq.zig").beq;
const bit = @import("instructions/bit.zig").bit;
const bne = @import("instructions/bne.zig").bne;
const bpl = @import("instructions/bpl.zig").bpl;
const brk = @import("instructions/brk.zig").brk;
const bmi = @import("instructions/bmi.zig").bmi;
const bvc = @import("instructions/bvc.zig").bvc;
const bvs = @import("instructions/bvs.zig").bvs;
const clc = @import("instructions/clc.zig").clc;
const cld = @import("instructions/cld.zig").cld;
const cli = @import("instructions/cli.zig").cli;
const clv = @import("instructions/clv.zig").clv;
const cmp = @import("instructions/cmp.zig").cmp;
const cpx = @import("instructions/cpx.zig").cpx;
const cpy = @import("instructions/cpy.zig").cpy;
const dcp = @import("instructions/dcp.zig").dcp;
const dec = @import("instructions/dec.zig").dec;
const dex = @import("instructions/dex.zig").dex;
const dey = @import("instructions/dey.zig").dey;
const eor = @import("instructions/eor.zig").eor;
const jmp = @import("instructions/jmp.zig").jmp;
const jsr = @import("instructions/jsr.zig").jsr;
const lax = @import("instructions/lax.zig").lax;
const lda = @import("instructions/lda.zig").lda;
const ldx = @import("instructions/ldx.zig").ldx;
const ldy = @import("instructions/ldy.zig").ldy;
const lsr = @import("instructions/lsr.zig").lsr;
const inc = @import("instructions/inc.zig").inc;
const inx = @import("instructions/inx.zig").inx;
const iny = @import("instructions/iny.zig").iny;
const isb = @import("instructions/isb.zig").isb;
const ora = @import("instructions/ora.zig").ora;
const pha = @import("instructions/pha.zig").pha;
const php = @import("instructions/php.zig").php;
const pla = @import("instructions/pla.zig").pla;
const plp = @import("instructions/plp.zig").plp;
const rla = @import("instructions/rla.zig").rla;
const rol = @import("instructions/rol.zig").rol;
const ror = @import("instructions/ror.zig").ror;
const rra = @import("instructions/rra.zig").rra;
const rti = @import("instructions/rti.zig").rti;
const rts = @import("instructions/rts.zig").rts;
const sbc = @import("instructions/sbc.zig").sbc;
const sec = @import("instructions/sec.zig").sec;
const sed = @import("instructions/sed.zig").sed;
const sei = @import("instructions/sei.zig").sei;
const sax = @import("instructions/sax.zig").sax;
const slo = @import("instructions/slo.zig").slo;
const sta = @import("instructions/sta.zig").sta;
const stx = @import("instructions/stx.zig").stx;
const sty = @import("instructions/sty.zig").sty;
const sre = @import("instructions/sre.zig").sre;
const tax = @import("instructions/tax.zig").tax;
const tay = @import("instructions/tay.zig").tay;
const tsx = @import("instructions/tsx.zig").tsx;
const txa = @import("instructions/txa.zig").txa;
const txs = @import("instructions/txs.zig").txs;
const tya = @import("instructions/tya.zig").tya;

pub const Addressing = union(enum) {
    imp,
    acc,
    rel: i8,
    imm: u8,
    zpg: u8,
    zpx: u8,
    zpy: u8,
    abs: u16,
    abx: std.meta.Tuple(&.{ u16, bool }),
    aby: std.meta.Tuple(&.{ u16, bool }),
    idx: std.meta.Tuple(&.{ u16, u8 }),
    idy: std.meta.Tuple(&.{ u16, u8, bool }),
};

pub const AddressingMode = enum {
    acc,
    imp,
    rel,
    imm,
    zpg,
    zpx,
    zpy,
    ind,
    abs,
    abx,
    aby,
    idx,
    idy,
};

pub const Instruction = enum {
    adc,
    @"and",
    asl,
    bcc,
    bcs,
    beq,
    bit,
    bmi,
    bne,
    bpl,
    brk,
    bvc,
    bvs,
    clc,
    cld,
    cli,
    clv,
    cmp,
    cpx,
    cpy,
    dec,
    dex,
    dey,
    eor,
    inc,
    inx,
    iny,
    jmp,
    jsr,
    lda,
    ldx,
    ldy,
    lsr,
    nop,
    ora,
    pha,
    php,
    pla,
    plp,
    rol,
    ror,
    rti,
    rts,
    sbc,
    sec,
    sed,
    sei,
    sta,
    stx,
    sty,
    tax,
    tay,
    tsx,
    txa,
    txs,
    tya,
    lax,
    sax,
    dcp,
    isb,
    slo,
    rla,
    sre,
    rra,
    hlt,
};

pub const Opcode = struct {
    instruction: Instruction,
    addressing_mode: AddressingMode,
    func: *const fn (*CPU, Addressing) void,
};

pub const Opcodes = [_]Opcode{
    .{ .instruction = .brk, .addressing_mode = .imp, .func = brk },
    .{ .instruction = .ora, .addressing_mode = .idx, .func = ora },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .slo, .addressing_mode = .idx, .func = slo },
    .{ .instruction = .nop, .addressing_mode = .zpg, .func = nop },
    .{ .instruction = .ora, .addressing_mode = .zpg, .func = ora },
    .{ .instruction = .asl, .addressing_mode = .zpg, .func = asl },
    .{ .instruction = .slo, .addressing_mode = .zpg, .func = slo },
    .{ .instruction = .php, .addressing_mode = .imp, .func = php },
    .{ .instruction = .ora, .addressing_mode = .imm, .func = ora },
    .{ .instruction = .asl, .addressing_mode = .acc, .func = asl },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .nop, .addressing_mode = .abs, .func = nop },
    .{ .instruction = .ora, .addressing_mode = .abs, .func = ora },
    .{ .instruction = .asl, .addressing_mode = .abs, .func = asl },
    .{ .instruction = .slo, .addressing_mode = .abs, .func = slo },
    .{ .instruction = .bpl, .addressing_mode = .rel, .func = bpl },
    .{ .instruction = .ora, .addressing_mode = .idy, .func = ora },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .slo, .addressing_mode = .idy, .func = slo },
    .{ .instruction = .nop, .addressing_mode = .zpx, .func = nop },
    .{ .instruction = .ora, .addressing_mode = .zpx, .func = ora },
    .{ .instruction = .asl, .addressing_mode = .zpx, .func = asl },
    .{ .instruction = .slo, .addressing_mode = .zpx, .func = slo },
    .{ .instruction = .clc, .addressing_mode = .imp, .func = clc },
    .{ .instruction = .ora, .addressing_mode = .aby, .func = ora },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .slo, .addressing_mode = .aby, .func = slo },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .ora, .addressing_mode = .abx, .func = ora },
    .{ .instruction = .asl, .addressing_mode = .abx, .func = asl },
    .{ .instruction = .slo, .addressing_mode = .abx, .func = slo },
    .{ .instruction = .jsr, .addressing_mode = .abs, .func = jsr },
    .{ .instruction = .@"and", .addressing_mode = .idx, .func = @"and" },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .rla, .addressing_mode = .idx, .func = rla },
    .{ .instruction = .bit, .addressing_mode = .zpg, .func = bit },
    .{ .instruction = .@"and", .addressing_mode = .zpg, .func = @"and" },
    .{ .instruction = .rol, .addressing_mode = .zpg, .func = rol },
    .{ .instruction = .rla, .addressing_mode = .zpg, .func = rla },
    .{ .instruction = .plp, .addressing_mode = .imp, .func = plp },
    .{ .instruction = .@"and", .addressing_mode = .imm, .func = @"and" },
    .{ .instruction = .rol, .addressing_mode = .acc, .func = rol },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .bit, .addressing_mode = .abs, .func = bit },
    .{ .instruction = .@"and", .addressing_mode = .abs, .func = @"and" },
    .{ .instruction = .rol, .addressing_mode = .abs, .func = rol },
    .{ .instruction = .rla, .addressing_mode = .abs, .func = rla },
    .{ .instruction = .bmi, .addressing_mode = .rel, .func = bmi },
    .{ .instruction = .@"and", .addressing_mode = .idy, .func = @"and" },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .rla, .addressing_mode = .idy, .func = rla },
    .{ .instruction = .nop, .addressing_mode = .zpx, .func = nop },
    .{ .instruction = .@"and", .addressing_mode = .zpx, .func = @"and" },
    .{ .instruction = .rol, .addressing_mode = .zpx, .func = rol },
    .{ .instruction = .rla, .addressing_mode = .zpx, .func = rla },
    .{ .instruction = .sec, .addressing_mode = .imp, .func = sec },
    .{ .instruction = .@"and", .addressing_mode = .aby, .func = @"and" },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .rla, .addressing_mode = .aby, .func = rla },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .@"and", .addressing_mode = .abx, .func = @"and" },
    .{ .instruction = .rol, .addressing_mode = .abx, .func = rol },
    .{ .instruction = .rla, .addressing_mode = .abx, .func = rla },
    .{ .instruction = .rti, .addressing_mode = .imp, .func = rti },
    .{ .instruction = .eor, .addressing_mode = .idx, .func = eor },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .sre, .addressing_mode = .idx, .func = sre },
    .{ .instruction = .nop, .addressing_mode = .zpg, .func = nop },
    .{ .instruction = .eor, .addressing_mode = .zpg, .func = eor },
    .{ .instruction = .lsr, .addressing_mode = .zpg, .func = lsr },
    .{ .instruction = .sre, .addressing_mode = .zpg, .func = sre },
    .{ .instruction = .pha, .addressing_mode = .imp, .func = pha },
    .{ .instruction = .eor, .addressing_mode = .imm, .func = eor },
    .{ .instruction = .lsr, .addressing_mode = .acc, .func = lsr },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .jmp, .addressing_mode = .abs, .func = jmp },
    .{ .instruction = .eor, .addressing_mode = .abs, .func = eor },
    .{ .instruction = .lsr, .addressing_mode = .abs, .func = lsr },
    .{ .instruction = .sre, .addressing_mode = .abs, .func = sre },
    .{ .instruction = .bvc, .addressing_mode = .rel, .func = bvc },
    .{ .instruction = .eor, .addressing_mode = .idy, .func = eor },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .sre, .addressing_mode = .idy, .func = sre },
    .{ .instruction = .nop, .addressing_mode = .zpx, .func = nop },
    .{ .instruction = .eor, .addressing_mode = .zpx, .func = eor },
    .{ .instruction = .lsr, .addressing_mode = .zpx, .func = lsr },
    .{ .instruction = .sre, .addressing_mode = .zpx, .func = sre },
    .{ .instruction = .cli, .addressing_mode = .imp, .func = cli },
    .{ .instruction = .eor, .addressing_mode = .aby, .func = eor },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .sre, .addressing_mode = .aby, .func = sre },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .eor, .addressing_mode = .abx, .func = eor },
    .{ .instruction = .lsr, .addressing_mode = .abx, .func = lsr },
    .{ .instruction = .sre, .addressing_mode = .abx, .func = sre },
    .{ .instruction = .rts, .addressing_mode = .imp, .func = rts },
    .{ .instruction = .adc, .addressing_mode = .idx, .func = adc },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .rra, .addressing_mode = .idx, .func = rra },
    .{ .instruction = .nop, .addressing_mode = .zpg, .func = nop },
    .{ .instruction = .adc, .addressing_mode = .zpg, .func = adc },
    .{ .instruction = .ror, .addressing_mode = .zpg, .func = ror },
    .{ .instruction = .rra, .addressing_mode = .zpg, .func = rra },
    .{ .instruction = .pla, .addressing_mode = .imp, .func = pla },
    .{ .instruction = .adc, .addressing_mode = .imm, .func = adc },
    .{ .instruction = .ror, .addressing_mode = .acc, .func = ror },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .jmp, .addressing_mode = .ind, .func = jmp },
    .{ .instruction = .adc, .addressing_mode = .abs, .func = adc },
    .{ .instruction = .ror, .addressing_mode = .abs, .func = ror },
    .{ .instruction = .rra, .addressing_mode = .abs, .func = rra },
    .{ .instruction = .bvs, .addressing_mode = .rel, .func = bvs },
    .{ .instruction = .adc, .addressing_mode = .idy, .func = adc },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .rra, .addressing_mode = .idy, .func = rra },
    .{ .instruction = .nop, .addressing_mode = .zpx, .func = nop },
    .{ .instruction = .adc, .addressing_mode = .zpx, .func = adc },
    .{ .instruction = .ror, .addressing_mode = .zpx, .func = ror },
    .{ .instruction = .rra, .addressing_mode = .zpx, .func = rra },
    .{ .instruction = .sei, .addressing_mode = .imp, .func = sei },
    .{ .instruction = .adc, .addressing_mode = .aby, .func = adc },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .rra, .addressing_mode = .aby, .func = rra },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .adc, .addressing_mode = .abx, .func = adc },
    .{ .instruction = .ror, .addressing_mode = .abx, .func = ror },
    .{ .instruction = .rra, .addressing_mode = .abx, .func = rra },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .sta, .addressing_mode = .idx, .func = sta },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .sax, .addressing_mode = .idx, .func = sax },
    .{ .instruction = .sty, .addressing_mode = .zpg, .func = sty },
    .{ .instruction = .sta, .addressing_mode = .zpg, .func = sta },
    .{ .instruction = .stx, .addressing_mode = .zpg, .func = stx },
    .{ .instruction = .sax, .addressing_mode = .zpg, .func = sax },
    .{ .instruction = .dey, .addressing_mode = .imp, .func = dey },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .txa, .addressing_mode = .imp, .func = txa },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .sty, .addressing_mode = .abs, .func = sty },
    .{ .instruction = .sta, .addressing_mode = .abs, .func = sta },
    .{ .instruction = .stx, .addressing_mode = .abs, .func = stx },
    .{ .instruction = .sax, .addressing_mode = .abs, .func = sax },
    .{ .instruction = .bcc, .addressing_mode = .rel, .func = bcc },
    .{ .instruction = .sta, .addressing_mode = .idy, .func = sta },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .nop, .addressing_mode = .idy, .func = nop },
    .{ .instruction = .sty, .addressing_mode = .zpx, .func = sty },
    .{ .instruction = .sta, .addressing_mode = .zpx, .func = sta },
    .{ .instruction = .stx, .addressing_mode = .zpy, .func = stx },
    .{ .instruction = .sax, .addressing_mode = .zpy, .func = sax },
    .{ .instruction = .tya, .addressing_mode = .imp, .func = tya },
    .{ .instruction = .sta, .addressing_mode = .aby, .func = sta },
    .{ .instruction = .txs, .addressing_mode = .imp, .func = txs },
    .{ .instruction = .nop, .addressing_mode = .aby, .func = nop },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .sta, .addressing_mode = .abx, .func = sta },
    .{ .instruction = .nop, .addressing_mode = .aby, .func = nop },
    .{ .instruction = .nop, .addressing_mode = .aby, .func = nop },
    .{ .instruction = .ldy, .addressing_mode = .imm, .func = ldy },
    .{ .instruction = .lda, .addressing_mode = .idx, .func = lda },
    .{ .instruction = .ldx, .addressing_mode = .imm, .func = ldx },
    .{ .instruction = .lax, .addressing_mode = .idx, .func = lax },
    .{ .instruction = .ldy, .addressing_mode = .zpg, .func = ldy },
    .{ .instruction = .lda, .addressing_mode = .zpg, .func = lda },
    .{ .instruction = .ldx, .addressing_mode = .zpg, .func = ldx },
    .{ .instruction = .lax, .addressing_mode = .zpg, .func = lax },
    .{ .instruction = .tay, .addressing_mode = .imp, .func = tay },
    .{ .instruction = .lda, .addressing_mode = .imm, .func = lda },
    .{ .instruction = .tax, .addressing_mode = .imp, .func = tax },
    .{ .instruction = .lax, .addressing_mode = .imm, .func = lax },
    .{ .instruction = .ldy, .addressing_mode = .abs, .func = ldy },
    .{ .instruction = .lda, .addressing_mode = .abs, .func = lda },
    .{ .instruction = .ldx, .addressing_mode = .abs, .func = ldx },
    .{ .instruction = .lax, .addressing_mode = .abs, .func = lax },
    .{ .instruction = .bcs, .addressing_mode = .rel, .func = bcs },
    .{ .instruction = .lda, .addressing_mode = .idy, .func = lda },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .lax, .addressing_mode = .idy, .func = lax },
    .{ .instruction = .ldy, .addressing_mode = .zpx, .func = ldy },
    .{ .instruction = .lda, .addressing_mode = .zpx, .func = lda },
    .{ .instruction = .ldx, .addressing_mode = .zpy, .func = ldx },
    .{ .instruction = .lax, .addressing_mode = .zpy, .func = lax },
    .{ .instruction = .clv, .addressing_mode = .imp, .func = clv },
    .{ .instruction = .lda, .addressing_mode = .aby, .func = lda },
    .{ .instruction = .tsx, .addressing_mode = .imp, .func = tsx },
    .{ .instruction = .nop, .addressing_mode = .aby, .func = nop },
    .{ .instruction = .ldy, .addressing_mode = .abx, .func = ldy },
    .{ .instruction = .lda, .addressing_mode = .abx, .func = lda },
    .{ .instruction = .ldx, .addressing_mode = .aby, .func = ldx },
    .{ .instruction = .lax, .addressing_mode = .aby, .func = lax },
    .{ .instruction = .cpy, .addressing_mode = .imm, .func = cpy },
    .{ .instruction = .cmp, .addressing_mode = .idx, .func = cmp },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .dcp, .addressing_mode = .idx, .func = dcp },
    .{ .instruction = .cpy, .addressing_mode = .zpg, .func = cpy },
    .{ .instruction = .cmp, .addressing_mode = .zpg, .func = cmp },
    .{ .instruction = .dec, .addressing_mode = .zpg, .func = dec },
    .{ .instruction = .dcp, .addressing_mode = .zpg, .func = dcp },
    .{ .instruction = .iny, .addressing_mode = .imp, .func = iny },
    .{ .instruction = .cmp, .addressing_mode = .imm, .func = cmp },
    .{ .instruction = .dex, .addressing_mode = .imp, .func = dex },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .cpy, .addressing_mode = .abs, .func = cpy },
    .{ .instruction = .cmp, .addressing_mode = .abs, .func = cmp },
    .{ .instruction = .dec, .addressing_mode = .abs, .func = dec },
    .{ .instruction = .dcp, .addressing_mode = .abs, .func = dcp },
    .{ .instruction = .bne, .addressing_mode = .rel, .func = bne },
    .{ .instruction = .cmp, .addressing_mode = .idy, .func = cmp },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .dcp, .addressing_mode = .idy, .func = dcp },
    .{ .instruction = .nop, .addressing_mode = .zpx, .func = nop },
    .{ .instruction = .cmp, .addressing_mode = .zpx, .func = cmp },
    .{ .instruction = .dec, .addressing_mode = .zpx, .func = dec },
    .{ .instruction = .dcp, .addressing_mode = .zpx, .func = dcp },
    .{ .instruction = .cld, .addressing_mode = .imp, .func = cld },
    .{ .instruction = .cmp, .addressing_mode = .aby, .func = cmp },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .dcp, .addressing_mode = .aby, .func = dcp },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .cmp, .addressing_mode = .abx, .func = cmp },
    .{ .instruction = .dec, .addressing_mode = .abx, .func = dec },
    .{ .instruction = .dcp, .addressing_mode = .abx, .func = dcp },
    .{ .instruction = .cpx, .addressing_mode = .imm, .func = cpx },
    .{ .instruction = .sbc, .addressing_mode = .idx, .func = sbc },
    .{ .instruction = .nop, .addressing_mode = .imm, .func = nop },
    .{ .instruction = .isb, .addressing_mode = .idx, .func = isb },
    .{ .instruction = .cpx, .addressing_mode = .zpg, .func = cpx },
    .{ .instruction = .sbc, .addressing_mode = .zpg, .func = sbc },
    .{ .instruction = .inc, .addressing_mode = .zpg, .func = inc },
    .{ .instruction = .isb, .addressing_mode = .zpg, .func = isb },
    .{ .instruction = .inx, .addressing_mode = .imp, .func = inx },
    .{ .instruction = .sbc, .addressing_mode = .imm, .func = sbc },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .sbc, .addressing_mode = .imm, .func = sbc },
    .{ .instruction = .cpx, .addressing_mode = .abs, .func = cpx },
    .{ .instruction = .sbc, .addressing_mode = .abs, .func = sbc },
    .{ .instruction = .inc, .addressing_mode = .abs, .func = inc },
    .{ .instruction = .isb, .addressing_mode = .abs, .func = isb },
    .{ .instruction = .beq, .addressing_mode = .rel, .func = beq },
    .{ .instruction = .sbc, .addressing_mode = .idy, .func = sbc },
    .{ .instruction = .hlt, .addressing_mode = .imp, .func = hlt },
    .{ .instruction = .isb, .addressing_mode = .idy, .func = isb },
    .{ .instruction = .nop, .addressing_mode = .zpx, .func = nop },
    .{ .instruction = .sbc, .addressing_mode = .zpx, .func = sbc },
    .{ .instruction = .inc, .addressing_mode = .zpx, .func = inc },
    .{ .instruction = .isb, .addressing_mode = .zpx, .func = isb },
    .{ .instruction = .sed, .addressing_mode = .imp, .func = sed },
    .{ .instruction = .sbc, .addressing_mode = .aby, .func = sbc },
    .{ .instruction = .nop, .addressing_mode = .imp, .func = nop },
    .{ .instruction = .isb, .addressing_mode = .aby, .func = isb },
    .{ .instruction = .nop, .addressing_mode = .abx, .func = nop },
    .{ .instruction = .sbc, .addressing_mode = .abx, .func = sbc },
    .{ .instruction = .inc, .addressing_mode = .abx, .func = inc },
    .{ .instruction = .isb, .addressing_mode = .abx, .func = isb },
};

test {
    std.testing.refAllDecls(@This());
}
