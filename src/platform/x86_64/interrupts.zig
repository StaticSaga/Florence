const std = @import("std");
const os = @import("root").os;

const platform  = os.platform;
const range     = os.lib.range.range;
const scheduler = os.thread.scheduler;

const idt = @import("idt.zig");
const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const thread = @import("thread.zig");

pub const num_handlers = 0x100;
pub const InterruptHandler = fn(*InterruptFrame)void;
pub const InterruptState = bool;

export var handlers: [256]InterruptHandler = [_]InterruptHandler {unhandled_interrupt} ** num_handlers;
var itable: *[256]idt.IdtEntry = undefined;
var raw_callbacks: [256](fn() callconv(.Naked) void) = undefined;

/// Use ist=2 for scheduler calls and ist=1 for interrupts
pub fn add_handler(idx: u8, f: InterruptHandler, interrupt: bool, priv_level: u2, ist: u3) void {
  itable[idx] = idt.entry(raw_callbacks[idx], interrupt, priv_level, ist);
  handlers[idx] = f;
}

pub fn init_interrupts() !void {
  pic.disable();
  itable = &idt.idt;

  inline for(range(num_handlers)) |intnum| {
    raw_callbacks[intnum] = make_handler(intnum);
    add_handler(intnum, unhandled_interrupt, true, 0, 0);
  }

  add_handler(0x0E, page_fault_handler, true, 0, 1);
  add_handler(0x6C, os.thread.preemption.bootstrap, true, 0, 0);
  std.debug.assert(handlers[0x6c] == os.thread.preemption.bootstrap);
  add_handler(0x6B, os.thread.preemption.wait_yield, true, 0, 2);
  add_handler(0xFF, spurious_handler, true, 0, 1);
}

fn spurious_handler(frame: *InterruptFrame) void {
}

fn type_page_fault(error_code: usize) !platform.PageFaultAccess {
  if(error_code & 0x8 != 0)
    return error.ReservedWrite;
  if(error_code & 0x10 != 0)
    return .InstructionFetch;
  if(error_code & 0x2 != 0)
    return .Write;
  return .Read;
}

fn page_fault_handler(frame: *InterruptFrame) void {
  const page_fault_addr = asm(
    "mov %%cr2, %[addr]"
    :[addr] "=r" (-> usize)
  );
  const page_fault_type = type_page_fault(frame.ec) catch |err| {
    os.log("Interrupts: Page fault at addr 0x{x}, but we couldn't determine what type. (error code was 0x{x}).\nCaught error {}.\n", .{page_fault_addr, frame.ec, @errorName(err)});
    frame.dump();
    os.platform.hang();
  };

  os.log("Interrupts: Page fault while {} at 0x{x}\n",
    .{
      switch(page_fault_type) {
        .Read => @as([]const u8, "reading"),
        .Write => "writing",
        .InstructionFetch => "fetching instruction",
      },
      page_fault_addr,
    }
  );

  platform.page_fault(page_fault_addr, (frame.ec & 1) != 0, page_fault_type, frame);
  os.platform.hang();
}

fn unhandled_interrupt(frame: *InterruptFrame) void {
  os.log("Interrupts: Unhandled interrupt: {}!\n", .{frame.intnum});
  frame.dump();
  frame.trace_stack();
  os.platform.hang();
}

fn is_exception(intnum: u64) bool {
  return switch(intnum) {
    0x00 ... 0x1F => true,

    else => false,
  };
}

fn name(intnum: u64) []const u8 {
  return switch(intnum) {
    0x00 => "Divide by zero",
    0x01 => "Debug",
    0x02 => "Non-maskable interrupt",
    0x03 => "Breakpoint",
    0x04 => "Overflow",
    0x05 => "Bound range exceeded",
    0x06 => "Invalid opcode",
    0x07 => "Device not available",
    0x08 => "Double fault",
    0x09 => "Coprocessor Segment Overrun",
    0x0A => "Invalid TSS",
    0x0B => "Segment Not Present",
    0x0C => "Stack-Segment Fault",
    0x0D => "General Protection Fault",
    0x0E => "Page Fault",
    0x0F => unreachable,
    0x10 => "x87 Floating-Point Exception",
    0x11 => "Alignment Check",
    0x12 => "Machine Check",
    0x13 => "SIMD Floating-Point Exception",
    0x14 => "Virtualization Exception",
    0x15 ... 0x1D => unreachable,
    0x1E => "Security Exception",

    else => unreachable,
  };
}

fn has_error_code(intnum: u64) bool {
  return switch(intnum) {
    // Exceptions
    0x00 ... 0x07 => false,
    0x08          => true,
    0x09          => false,
    0x0A ... 0x0E => true,
    0x0F ... 0x10 => false,
    0x11          => true,
    0x12 ... 0x14 => false,
    //0x15 ... 0x1D => unreachable,
    0x1E          => true,
    //0x1F          => unreachable,

    // Other interrupts
    else => false,
  };
}

pub fn make_handler(comptime intnum: u64) idt.InterruptHandler {
  return struct {
    fn func() callconv(.Naked) void {
      if(comptime !has_error_code(intnum)) {
        asm volatile(
          \\push $0
        );
      }
      asm volatile(
        \\push %[intnum]
        \\jmp interrupt_common
        :
        : [intnum] "N{dx}" (@as(u8, intnum))
      );
    }
  }.func;
}

pub const InterruptFrame = packed struct {
  es: u64,
  ds: u64,
  fs: u64,
  gs: u64,
  r15: u64,
  r14: u64,
  r13: u64,
  r12: u64,
  r11: u64,
  r10: u64,
  r9:  u64,
  r8:  u64,
  rdi: u64,
  rsi: u64,
  rbp: u64,
  rdx: u64,
  rcx: u64,
  rbx: u64,
  rax: u64,
  intnum: u64,
  ec:  u64,
  rip: u64,
  cs:  u64,
  eflags: u64,
  rsp: u64, 
  ss:  u64,

  pub fn dump(self: *@This()) void {
    os.log("FRAME DUMP:\n", .{});
    os.log("RAX={x:0>16} RBX={x:0>16} RCX={x:0>16} RDX={x:0>16}\n", .{self.rax, self.rbx, self.rcx, self.rdx});
    os.log("RSI={x:0>16} RDI={x:0>16} RBP={x:0>16} RSP={x:0>16}\n", .{self.rsi, self.rdi, self.rbp, self.rsp});
    os.log("R8 ={x:0>16} R9 ={x:0>16} R10={x:0>16} R11={x:0>16}\n", .{self.r8,  self.r9,  self.r10, self.r11});
    os.log("R12={x:0>16} R13={x:0>16} R14={x:0>16} R15={x:0>16}\n", .{self.r12, self.r13, self.r14, self.r15});
    os.log("RIP={x:0>16} int={x:0>16} ec ={x:0>16}\n",              .{self.rip, self.intnum, self.ec});
  }

  pub fn trace_stack(self: *@This()) void {
    os.lib.debug.dump_frame(self.rbp, self.rip);
  }
};

export fn interrupt_common() callconv(.Naked) void {
  asm volatile(
    \\push %%rax
    \\push %%rbx
    \\push %%rcx
    \\push %%rdx
    \\push %%rbp
    \\push %%rsi
    \\push %%rdi
    \\push %%r8
    \\push %%r9
    \\push %%r10
    \\push %%r11
    \\push %%r12
    \\push %%r13
    \\push %%r14
    \\push %%r15
    \\mov %%gs, %%rax
    \\push %%rax
    \\mov %%fs, %%rax
    \\push %%rax
    \\mov %%ds, %%rax
    \\push %%rax
    \\mov %%es, %%rax
    \\push %%rax
    \\mov %%rsp, %%rdi
    \\mov %[dsel], %%ax
    \\mov %%ax, %%es
    \\mov %%ax, %%ds
    \\mov %%ax, %%fs
    \\mov %%ax, %%gs
    \\call interrupt_handler
    \\pop %%rax
    \\mov %%es, %%rax
    \\pop %%rax
    \\mov %%ds, %%rax
    \\pop %%fs
    \\pop %%gs
    \\pop %%r15
    \\pop %%r14
    \\pop %%r13
    \\pop %%r12
    \\pop %%r11
    \\pop %%r10
    \\pop %%r9
    \\pop %%r8
    \\pop %%rdi
    \\pop %%rsi
    \\pop %%rbp
    \\pop %%rdx
    \\pop %%rcx
    \\pop %%rbx
    \\pop %%rax
    \\add $16, %%rsp // Pop error code and interrupt number
    \\iretq
    :
    : [dsel] "i" (gdt.selector.data64)
  );
  unreachable;
}

export fn interrupt_handler(frame: u64) void {
  const int_frame = @intToPtr(*InterruptFrame, frame);
  if(int_frame.intnum < num_handlers) {
    handlers[int_frame.intnum](int_frame);
  }
}
