const testing = @import("../testing/setup.zig");

test "IRQ" {
    var cpu = testing.createCPU();
    cpu.sp = 0xff;
    cpu.i = false;
    cpu.irq_requested = true;
    cpu.write(0x1ff, 0xff);
    cpu.write(0x1fe, 0xff);
    cpu.write(0xfffe, 0xac);
    cpu.write(0xffff, 0x04);
    for (0..7) |_| {
        cpu.process();
    }
    try testing.expectEqual(0x4ac, cpu.pc);
    try testing.expectEqual(0, cpu.read(0x1ff));
    try testing.expectEqual(0, cpu.read(0x1fe));
    try testing.expectEqual(cpu.getP() & ~@as(u8, 0x14), cpu.read(0x1fd));
}

// test('nmi', () => {
//   const mmu = new BufferMapper()
//   const cpu = new CPU(mmu)
//   cpu.sp = 0xff
//   cpu.nmiRequested = true
//   cpu.interruptDisabled = false
//   mmu.data[0xfffa] = 0xac
//   mmu.data[0xfffb] = 0x04
//   const g = cpu.run()
//   for (let i = 0; i < 7; i++) g.next()
//   expect(cpu.pc).toBe(0x4ac)
//   expect(mmu.data[0x1ff]).toBe(0)
//   expect(mmu.data[0x1fe]).toBe(0)
//   expect(mmu.data[0x1fd]).toBe(cpu.status & ~0x14)
// })

// test('rst', () => {
//   const mmu = new BufferMapper()
//   const cpu = new CPU(mmu)
//   cpu.sp = 0xff
//   cpu.interruptDisabled = false
//   cpu.rstRequested = true
//   mmu.data[0x1ff] = 0xff
//   mmu.data[0x1fe] = 0xff
//   mmu.data[0xfffc] = 0xac
//   mmu.data[0xfffd] = 0x04
//   const g = cpu.run()
//   for (let i = 0; i < 7; i++) g.next()
//   expect(cpu.pc).toBe(0x4ac)
//   expect(mmu.data[0x1ff]).toBe(0xff)
//   expect(mmu.data[0x1fe]).toBe(0xff)
//   expect(cpu.interruptDisabled).toBe(true)
// })
