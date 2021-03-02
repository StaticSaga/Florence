const os = @import("root").os;
const std = @import("std");
const libalign = os.lib.libalign;

/// Class that handles calling a function with any arguments on a new stack
/// Used as a helper for task creation in platform-specific code
pub const NewTaskEntry = struct {
    /// Callback that should be executed in a new task
    function: fn (*NewTaskEntry) void,

    pub fn alloc_on_stack(func: anytype, args: anytype, stack_top: usize, stack_botton: usize) *NewTaskEntry {
        comptime const Args = @TypeOf(args);
        comptime const Func = @TypeOf(func);
        // Method: specify subtype with specific types of func and args
        const Wrapper = struct {
            entry: NewTaskEntry = .{ .function = invoke },
            function: Func,
            args: Args,
            /// Implementation of invoke
            fn invoke(entry: *NewTaskEntry) void {
                const self = @fieldParentPtr(@This(), "entry", entry);
                @call(.{}, self.function, self.args) catch |err| {
                    os.log("Task has finished with error {s}\n", .{@errorName(err)});
                };
                os.thread.scheduler.exit_task();
            }
            /// Creates Wrapper on the stack
            fn create(function: anytype, arguments: anytype, boot_stack_top: usize, boot_stack_bottom: usize) *@This() {
                const addr = libalign.align_down(usize, @alignOf(@This()), boot_stack_top - @sizeOf(@This()));
                std.debug.assert(addr > boot_stack_bottom);
                const wrapper_ptr = @intToPtr(*@This(), addr);
                wrapper_ptr.* = .{
                    .function = function,
                    .args = arguments,
                };
                return wrapper_ptr;
            }
        };
        return &Wrapper.create(func, args, stack_top, stack_botton).entry;
    }
};