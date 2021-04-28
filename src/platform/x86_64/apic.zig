const os = @import("root").os;
const std = @import("std");
const builtin = @import("builtin");
const interrupts = @import("interrupts.zig");

// LAPIC

var lapic: *volatile [0x100]u32 = undefined;

pub fn enable() void {
  const phy = IA32_APIC_BASE.read() & 0xFFFFF000; // ignore flags
  lapic = os.platform.phys_ptr(*volatile [0x100]u32).from_int(phy).get_uncached();
  lapic[SPURIOUS] |= @as(u32, 0x100) | interrupts.spurious_vector; // bit 8 = lapic enable, bit 7-0 = spurious vector
}

pub fn eoi() void {
  lapic[EOI] = 0;
}

pub fn timer(ticks: u32, div: u32, vec: u32) void {
  lapic[LVT_TIMER] = vec | TIMER_MODE_PERIODIC;
  lapic[TIMER_DIV] = div;
  lapic[TIMER_INITCNT] = ticks;
}


// ACPI information

fn handle_processor(apic_id: u32) void {
  
}

const Override = struct {
  gsi: u32,
  flags: u16,
  ioapic_id: u8,
};

var source_overrides = [1]?Override{null} ** 0x100;

/// Routes the legacy irq to given lapic vector
/// Returns the GSI in case you want to disable it later
pub fn route_irq(lapic_id: u32, irq: u8, vector: u8) u32 {
  const gsi_mapping = map_irq_to_gsi(irq);
  route_gsi_ioapic(gsi_mapping.ioapic_id, lapic_id, vector, gsi_mapping.gsi, gsi_mapping.flags);
  return gsi_mapping.gsi;
}

/// Route a GSI to the given lapic vector
pub fn route_gsi(lapic_id: u32, vector: u8, gsi: u32, flags: u16) void {
  route_gsi_ioapic(gsi_to_ioapic(gsi), lapic_id, vector, gsi, flags);
}

fn route_gsi_ioapic(ioapic_id: u8, lapic_id: u32, vector: u8, gsi: u32, flags: u16) void {
  const value = 0
    | (@as(u64, vector) << 0)
    | (@as(u64, flags & 0b1010) << 12)
    | (@as(u64, lapic_id) << 56)
  ;

  const ioapic = ioapics[ioapic_id].?;
  const gsi_offset = (gsi - ioapic.gsi_base) * 2 + 0x10;

  ioapic.write(gsi_offset + 0, @truncate(u32, value));
  ioapic.write(gsi_offset + 1, @truncate(u32, value >> 32));
}

fn map_irq_to_gsi(irq: u8) Override {
  return source_overrides[irq] orelse Override{.gsi = @as(u32, irq), .flags = 0, .ioapic_id = gsi_to_ioapic(irq), };
}

fn handle_interrupt_source_override(ioapic_id: u8, irq: u8, gsi: u32, flags: u16) void {
  // We can probably filter away overrides where irq == gsi and flags == 0
  // Until we have a reason to do so, let's not.
  source_overrides[irq] = .{
    .gsi = gsi,
    .flags = flags,
    .ioapic_id = ioapic_id,
  };
  os.log("Interrupt source override {}: {}\n", .{irq, source_overrides[irq]});
}

const IOAPIC = struct {
  phys: usize,
  gsi_base: u32,

  fn reg(self: *const @This(), offset: usize) *volatile u32 {
    return os.platform.phys_ptr(*volatile u32).from_int(self.phys + offset).get_uncached();
  }

  fn write(self: *const @This(), offset: u32, value: u32) void {
    self.reg(0x00).* = offset;
    self.reg(0x10).* = value;
  }

  fn read(self: *const @This(), offset: u32) u32 {
    self.reg(0x00).* = offset;
    return self.reg(0x10).*;
  }

  fn gsi_count(self: *const @This()) u32 {
    return (self.read(1) >> 16) & 0xFF;
  }
};

fn gsi_to_ioapic(gsi: u32) u8 {
  for(ioapics) |ioa_o, idx| {
    if(ioa_o) |ioa| {
      const gsi_count = ioa.gsi_count();
      if(ioa.gsi_base <= gsi and gsi < ioa.gsi_base + gsi_count)
        return @intCast(u8, idx);
    }
  }
  os.log("GSI: {}\n", .{gsi});
  @panic("Can't find ioapic for gsi!");
}

var ioapics = [1]?IOAPIC{null} ** os.config.kernel.x86_64.max_ioapics;

fn handle_ioapic(ioapic_id: u8, ioapic_addr: usize, gsi_base: u32) void {
  ioapics[ioapic_id] = .{ .phys = ioapic_addr, .gsi_base = gsi_base, };
}

pub fn handle_madt(madt: []u8) void {
  os.log("APIC: Got MADT (size={x})\n", .{madt.len});

  var offset: u64 = 0x2C;
  while(offset + 2 <= madt.len) {
    const kind = madt[offset + 0];
    const size = madt[offset + 1];

    const data = madt[offset .. offset + size];

    if(offset + size >= madt.len)
      break;

    switch(kind) {
      0x00 => {
        std.debug.assert(size >= 8);
        const apic_id = data[3];
        const flags = std.mem.readIntNative(u32, data[4..8]);
        if(flags & 0x3 != 0)
          handle_processor(@as(u32, apic_id));
      },
      0x01 => {
        std.debug.assert(size >= 12);
        const ioapic_id = data[2];
        const addr = std.mem.readIntNative(u32, data[4..8]);
        const gsi_base = std.mem.readIntNative(u32, data[8..12]);
        handle_ioapic(ioapic_id, addr, gsi_base);
      },
      0x02 => {
        std.debug.assert(size >= 10);
        const ioapic_id = data[2];
        const irq = data[3];
        const gsi = std.mem.readIntNative(u32, data[4..8]);
        const flags = std.mem.readIntNative(u16, data[8..10]);
        handle_interrupt_source_override(ioapic_id, irq, gsi, flags);
      },
      0x03 => {
        std.debug.assert(size >= 8);
        os.log("APIC: TODO: NMI source\n", .{});
      },
      0x04 => {
        std.debug.assert(size >= 6);
        os.log("APIC: TODO: LAPIC Non-maskable interrupt\n", .{});
      },
      0x05 => {
        std.debug.assert(size >= 12);
        os.log("APIC: TODO: LAPIC addr override\n", .{});
      },
      0x06 => {
        std.debug.assert(size >= 16);
        os.log("APIC: TODO: I/O SAPIC\n", .{});
      },
      0x07 => {
        std.debug.assert(size >= 17);
        os.log("APIC: TODO: Local SAPIC\n", .{});
      },
      0x08 => {
        std.debug.assert(size >= 16);
        os.log("APIC: TODO: Platform interrupt sources\n", .{});
      },
      0x09 => {
        std.debug.assert(size >= 16);
        const flags   = std.mem.readIntNative(u32, data[8..12]);
        const apic_id = std.mem.readIntNative(u32, data[12..16]);
        if(flags & 0x3 != 0)
          handle_processor(apic_id);
      },
      0x0A => {
        std.debug.assert(size >= 12);
        os.log("APIC: TODO: LX2APIC NMI\n", .{});
      },
      else => {
        os.log("APIC: Unknown MADT entry: 0x{X}\n", .{kind});
      },
    }

    offset += size;
  }
}

const IA32_APIC_BASE = @import("regs.zig").MSR(u64, 0x0000001B);
const LVT_TIMER = 0x320 / 4;
const TIMER_MODE_PERIODIC = 1 << 17;
const TIMER_DIV = 0x3E0 / 4;
const TIMER_INITCNT = 0x380 / 4;
const SPURIOUS = 0xF0 / 4;
const EOI = 0xB0 / 4;
