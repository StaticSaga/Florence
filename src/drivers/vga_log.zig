const libalign = @import("../lib/align.zig");

const paging = @import("../paging.zig");
const pmm = @import("../pmm.zig");
const log = @import("../logger.zig").log;

const page_size = @import("../platform.zig").page_sizes[0];
const arch = @import("builtin").arch;

const Framebuffer = struct {
  x_pos: u64 = 0,
  y_pos: u64 = 0,
};

var framebuffer: ?Framebuffer = null;

pub fn register() void {
  if(arch == .x86_64) {
    relocate_fb();
    framebuffer = Framebuffer{};
    log("vga_log ready!\n", .{});
  }
}

pub fn relocate_fb() void {
  if(arch == .x86_64) {
    const vga_size = 80 * 25 * 2;
    const vga_page_low = libalign.align_down(usize, page_size, 0xB8000);
    const vga_page_high = libalign.align_up(usize, page_size, 0xB8000 + vga_size);

    paging.map_phys_range(vga_page_low, vga_page_high, paging.wc(paging.mmio())) catch |err| {
      log(":/ rip couldn't map vga: {}\n", .{@errorName(err)});
      return;
    };
  }
}

fn scroll_buffer() void {
  unreachable;
}

fn feed_line() void {
  framebuffer.?.x_pos = 0;
  if(framebuffer.?.y_pos == 24) {
    scroll_buffer();
  }
  else {
    framebuffer.?.y_pos += 1;
  }
}

pub fn putch(ch: u8) void {
  if(arch == .x86_64) {
    if(framebuffer == null)
      return;

    if(ch == '\n') {
      feed_line();
      return;
    }

    if(framebuffer.?.x_pos == 80)
      feed_line();

    pmm.access_phys(u8, 0xB8000)[(framebuffer.?.y_pos * 80 + framebuffer.?.x_pos) * 2] = ch;
    framebuffer.?.x_pos += 1;
  }
}