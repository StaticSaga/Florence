pub const mmio_serial = @import("io/mmio_serial.zig");
pub const vesa_log    = @import("io/vesa_log.zig");
pub const vga_log     = @import("io/vga_log.zig");

pub const ahci        = @import("disk/ahci.zig");

pub const virtio_gpu  = @import("virtio/virtio-gpu.zig");

pub const hid = .{
  .keyboard = @import("hid/keyboard.zig"),
};
