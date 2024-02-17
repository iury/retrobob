const testing = @import("testing/setup.zig");
const DummyDMC = @import("testing/DummyDMC.zig");

test "DMA: halting CPU" {
    var cpu = testing.createCPU();
    cpu.process();
    try testing.expectEqual(1, cpu.pc);

    cpu.reset();
    cpu.oam_dma = true;
    cpu.process();
    try testing.expectEqual(0, cpu.pc);

    cpu.reset();
    cpu.dmc_dma = true;
    cpu.process();
    try testing.expectEqual(0, cpu.pc);
}

test "DMA: DMC cycles" {
    // 3 cycles if first is a 'get'
    var cpu = testing.createCPU();
    cpu.dmc_dma = true;
    cpu.write(0x100, 0x42);
    cpu.dmc_address = 0x100;
    cpu.dma_cycle = .put;
    cpu.dmc.set(0);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .dmc_dummy_read);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .put and cpu.dma_status == .alignment);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .idle and cpu.pc == 0 and cpu.dmc.get() == 0x42);

    // 4 cycles if first is a 'put'
    cpu.reset();
    cpu.dmc_dma = true;
    cpu.dmc_address = 0x100;
    cpu.dma_cycle = .get;
    cpu.dmc.set(0);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .put and cpu.dma_status == .dmc_dummy_read);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .alignment);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .put and cpu.dma_status == .alignment);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .idle and cpu.pc == 0 and cpu.dmc.get() == 0x42);

    // 5 cycles if the next CPU cycle is a write
    cpu.reset();
    cpu.dmc_dma = true;
    cpu.dmc_address = 0x100;
    cpu.dma_cycle = .put;
    cpu.next_cycle = .write;
    cpu.dmc.set(0);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .halting);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .put and cpu.dma_status == .dmc_dummy_read);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .alignment);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .put and cpu.dma_status == .alignment);
    cpu.process();
    try testing.expect(cpu.dma_cycle == .get and cpu.dma_status == .idle and cpu.pc == 0 and cpu.dmc.get() == 0x42);
}

test "DMA: OAM cycles" {
    // 513 cycles
    var cpu = testing.createCPU();
    cpu.oam_dma = true;
    cpu.oam_address = 0xAA00;
    cpu.dma_cycle = .get;
    cpu.write(0xAAFF, 0x42);
    for (0..513) |_| cpu.process();
    try testing.expect(cpu.read(0x2004) == 0x42 and cpu.dma_status == .idle and cpu.pc == 0);

    // +1 for alignment
    cpu.reset();
    cpu.oam_dma = true;
    cpu.oam_address = 0xAA00;
    cpu.dma_cycle = .put;
    cpu.write(0xAAFF, 0xEC);
    for (0..514) |_| cpu.process();
    try testing.expect(cpu.read(0x2004) == 0xEC and cpu.dma_status == .idle and cpu.pc == 0);
}

test "DMA: OAM + DMC" {
    var cpu = testing.createCPU();
    cpu.dmc_dma = true;
    cpu.oam_dma = true;
    cpu.dmc_address = 0x100;
    cpu.oam_address = 0xAA00;
    cpu.dma_cycle = .put;
    cpu.dmc.set(0);
    cpu.write(0x100, 0x24);
    cpu.write(0xAAFF, 0x42);
    for (0..516) |_| cpu.process();
    try testing.expect(cpu.dmc.get() == 0x24 and cpu.read(0x2004) == 0x42 and cpu.dma_status == .idle and cpu.pc == 0);
}
