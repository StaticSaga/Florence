pub const bitfields = @import("bitfields.zig");
pub const bitset = @import("bitset.zig");
pub const buddy = @import("buddy.zig");
pub const debug = @import("debug.zig");
pub const libalign = @import("libalign.zig");
pub const logger = @import("logger.zig");
pub const packed_int = @import("packed_int.zig").packed_int;
pub const panic = @import("panic.zig");
pub const range = @import("range.zig");
pub const range_alloc = @import("range_alloc.zig");
pub const source = @import("source.zig");
pub const tar = @import("tar.zig");
pub const vital = @import("vital.zig");
pub const rbtree = @import("rbtree.zig");
pub const atmcqueue = @import("atomic_queue.zig");
pub const handle_table = @import("handle_table.zig");

pub const lai = @cImport({
  @cInclude("lai/core.h");
  @cInclude("lai/error.h");
  @cInclude("lai/host.h");
  @cInclude("lai/drivers/ec.h");
  @cInclude("lai/drivers/timer.h");
  @cInclude("lai/helpers/pc-bios.h");
  @cInclude("lai/helpers/pci.h");
  @cInclude("lai/helpers/pm.h");
  @cInclude("lai/helpers/resource.h");
  @cInclude("lai/helpers/sci.h");
});

pub fn get_index(ptr: anytype, slice: []@TypeOf(ptr.*)) usize {
    return (@ptrToInt(ptr) - @ptrToInt(slice.ptr)) / @sizeOf(@TypeOf(ptr.*));
}
