const os = @import("root").os;
const arch = @import("builtin").arch;

const libalign = os.lib.libalign;

const paging = os.memory.paging;
const pmm    = os.memory.pmm;

const page_size = os.platform.paging.page_sizes[0];

const Framebuffer = struct {
  x_pos: u64 = 0,
  y_pos: u64 = 0,
};

var framebuffer: ?Framebuffer = null;

pub fn register() void {
  if(arch == .x86_64) {
    framebuffer = Framebuffer{};
  }
}

fn buffer(comptime T: type) [*]volatile T {
  return os.platform.phys_ptr([*]volatile T).from_int(0xB8000).get_uncached();
}

fn scroll_buffer() void {
  {
    var y: u64 = 1;
    while(y < 25) {
      @memcpy(buffer(u8) + (y-1) * 80 * 2, buffer(u8) + y * 80 * 2, 80 * 2);
      y += 1;
    }
  }
  {
    var ptr = buffer(u8) + 24 * 80 * 2;
    var x: u64 = 0;
    while(x < 80) {
      ptr[0] = ' ';
      ptr[1] = 0x07;
      ptr += 2;
      x += 1;
    }
  }
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

    buffer(u16)[(framebuffer.?.y_pos * 80 + framebuffer.?.x_pos)] = 0x0700 | @as(u16, ch);
    framebuffer.?.x_pos += 1;
  }
}
