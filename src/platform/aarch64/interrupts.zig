const os = @import("root").os;

pub const InterruptState = bool;

pub fn get_and_disable_interrupts() InterruptState {
  // Get interrupt mask flag
  var daif = asm volatile("MRS %[daif_val], DAIF" : [daif_val] "=r" (-> u64));

  // Set the flag
  asm volatile("MSR DAIFSET, 2" ::: "memory");
  
  // Check if it was set
  return (daif >> 7) & 1 == 0;
}

pub fn set_interrupts(s: InterruptState) void {
  if(s) {
    // Enable interrupts
    asm volatile("MSR DAIFCLR, 2" ::: "memory");
  } else {
    // Disable interrupts
    asm volatile("MSR DAIFSET, 2" ::: "memory");
  }
}

pub const InterruptFrame = struct {
  spsr: u64,
  pc: u64,
  x31: u64,
  x30: u64,
  x29: u64,
  x28: u64,
  x27: u64,
  x26: u64,
  x25: u64,
  x24: u64,
  x23: u64,
  x22: u64,
  x21: u64,
  x20: u64,
  x19: u64,
  x18: u64,
  x17: u64,
  x16: u64,
  x15: u64,
  x14: u64,
  x13: u64,
  x12: u64,
  x11: u64,
  x10: u64,
  x9: u64,
  x8: u64,
  x7: u64,
  x6: u64,
  x5: u64,
  x4: u64,
  x3: u64,
  x2: u64,
  x1: u64,
  x0: u64,
  sp: u64,
  _: u64,

  pub fn dump(self: *const @This()) void {
    os.log("FRAME DUMP:\n", .{});
    os.log("X0 ={x:0>16} X1 ={x:0>16} X2 ={x:0>16} X3 ={x:0>16}\n", .{self.x0,  self.x1,  self.x2,  self.x3});
    os.log("X4 ={x:0>16} X5 ={x:0>16} X6 ={x:0>16} X7 ={x:0>16}\n", .{self.x4,  self.x5,  self.x6,  self.x7});
    os.log("X8 ={x:0>16} X9 ={x:0>16} X10={x:0>16} X11={x:0>16}\n", .{self.x8,  self.x9,  self.x10, self.x11});
    os.log("X12={x:0>16} X13={x:0>16} X14={x:0>16} X15={x:0>16}\n", .{self.x12, self.x13, self.x14, self.x15});
    os.log("X16={x:0>16} X17={x:0>16} X18={x:0>16} X19={x:0>16}\n", .{self.x16, self.x17, self.x18, self.x19});
    os.log("X20={x:0>16} X21={x:0>16} X22={x:0>16} X23={x:0>16}\n", .{self.x20, self.x21, self.x22, self.x23});
    os.log("X24={x:0>16} X25={x:0>16} X26={x:0>16} X27={x:0>16}\n", .{self.x24, self.x25, self.x26, self.x27});
    os.log("X28={x:0>16} X29={x:0>16} X30={x:0>16} X31={x:0>16}\n", .{self.x28, self.x29, self.x30, self.x31});
    os.log("PC ={x:0>16} SP ={x:0>16} SPSR={x:0>16}\n",             .{self.pc,  self.sp,  self.spsr});
  }

  pub fn trace_stack(self: *const @This()) void {
    os.lib.debug.dump_frame(self.x29, self.pc);
  }
};

export fn interrupt_common() callconv(.Naked) void {
  asm volatile(
    \\STP X3,  X2,  [SP, #-0x10]!
    \\STP X5,  X4,  [SP, #-0x10]!
    \\STP X7,  X6,  [SP, #-0x10]!
    \\STP X9,  X8,  [SP, #-0x10]!
    \\STP X11, X10, [SP, #-0x10]!
    \\STP X13, X12, [SP, #-0x10]!
    \\STP X15, X14, [SP, #-0x10]!
    \\STP X17, X16, [SP, #-0x10]!
    \\STP X19, X18, [SP, #-0x10]!
    \\STP X21, X20, [SP, #-0x10]!
    \\STP X23, X22, [SP, #-0x10]!
    \\STP X25, X24, [SP, #-0x10]!
    \\STP X27, X26, [SP, #-0x10]!
    \\STP X29, X28, [SP, #-0x10]!
    \\STP X31, X30, [SP, #-0x10]!
    \\MRS X0, SPSR_EL1
    \\MRS X1, ELR_EL1
    \\STP X0,  X1, [SP, #-0x10]!
    \\MOV X0,  SP
    \\BL interrupt_handler
    \\LDP X0, X1, [SP], 0x10
    \\MSR ELR_EL1, X1
    \\MSR SPSR_EL1, X1
    \\LDP X31, X30, [SP], 0x10
    \\LDP X29, X28, [SP], 0x10
    \\LDP X27, X26, [SP], 0x10
    \\LDP X25, X24, [SP], 0x10
    \\LDP X23, X22, [SP], 0x10
    \\LDP X21, X20, [SP], 0x10
    \\LDP X19, X18, [SP], 0x10
    \\LDP X17, X16, [SP], 0x10
    \\LDP X15, X14, [SP], 0x10
    \\LDP X13, X12, [SP], 0x10
    \\LDP X11, X10, [SP], 0x10
    \\LDP X9,  X8,  [SP], 0x10
    \\LDP X7,  X6,  [SP], 0x10
    \\LDP X5,  X4,  [SP], 0x10
    \\LDP X3,  X2,  [SP], 0x10
    \\
    \\// Critical section
    \\MSR DAIFSET, #0xF
    \\
    \\// Make the current SP the interrupt stack
    \\MSR SPSel, 1
    \\MRS X0, SP_EL0
    \\MOV SP, X0
    \\
    \\// Restore old stack pointer
    \\LDP X1, XZR, [SP, #0x10] // Load stack poiner
    \\MSR SP_EL0, X1 // Write old stack pointer to SP0
    \\LDP X1,  X0,  [SP], 0x20
    \\MSR SPSel, 0
    \\ERET
  );
  unreachable;
}

/// The vector which uses the already selected interrupt stack
export fn interrupt_irq_stack() callconv(.Naked) void {
  asm volatile(
    \\STP X1, X0, [SP, #-0x20]!
    \\MRS X1, SP_EL0
    \\STP X1, XZR, [SP, #0x10] // Store old stack pointer
    \\B interrupt_common
  );
  unreachable;
}

/// The vector which switches to the per-CPU scheduler stack
export fn interrupt_sched_stack() callconv(.Naked) void {
  asm volatile(
    \\STP X0, X1, [SP, #-0x10]!
    \\MRS X0, TPIDR_EL1 // Get the current cpu struct
    \\LDR X0, [X0, %[sched_stack_offset]] // Get the CPU scheduler stack
    \\MRS X1, SP_EL0
    \\STP X1, XZR, [X0, #-0x10]! // Push SP0 onto the scheduler stack
    \\MSR SP_EL0, X0 // Use our new, shiny call stack
    \\LDP X0, X1, [SP], 0x10
    \\MSR SPSel, #0 // Switch to it
    \\STP X1, X0, [SP, #-0x10]!
    \\B interrupt_common
    :
    : [sched_stack_offset] "i" (@as(usize, @byteOffsetOf(os.platform.smp.CoreData, "sched_stack")))
  );
  unreachable;
}

/// The vector which switches to the per-task syscall stack
export fn interrupt_syscall_stack() callconv(.Naked) void {
  asm volatile(
    \\STP X0, X1, [SP, #-0x10]!
    \\MRS X0, TPIDR_EL1 // Get the current cpu struct
    \\LDR X0, [X0, %[task_offset]] // Get the task
    \\LDR X0, [X0, %[syscall_stack_offset]]
    \\MRS X1, SP_EL0
    \\STP X1, XZR, [X0, #-0x10]! // Push SP0 onto the syscall stack
    \\MSR SP_EL0, X0 // Use our new, shiny syscall stack
    \\LDP X0, X1, [SP], 0x10
    \\MSR SPSel, #0 // Switch to it
    \\STP X1, X0, [SP, #-0x10]!
    \\B interrupt_common
    :
    : [task_offset] "i" (@as(usize, @byteOffsetOf(os.platform.smp.CoreData, "current_task")))
    , [syscall_stack_offset] "i" (@as(usize, @byteOffsetOf(os.thread.Task, "stack")))
  );
  unreachable;
}

/// The handler for everything else, which should cause some kind
/// of panic or similar.
export fn unhandled_vector() callconv(.Naked) void {
  // We don't plan on returning, calling the scheduler
  // nor enabling interrupts in this handler one, so
  // we can just use any handler here
  asm volatile(
    \\B interrupt_irq_stack
  );
  unreachable;
}

comptime {
  asm(
    \\.section .text.evt
    \\.balign 0x800
    \\.global exception_vector_table; exception_vector_table:
    \\ // Normal IRQs/scheduler calls from within kernel
    \\.balign 0x80; B interrupt_sched_stack // curr_el_sp0_sync
    \\.balign 0x80; B interrupt_irq_stack   // curr_el_sp0_irq
    \\.balign 0x80; B interrupt_irq_stack   // curr_el_sp0_fiq
    \\.balign 0x80; B unhandled_vector      // curr_el_sp0_serror
    \\ // The following 4 are unsupported as we only use spx with interrupts disabled,
    \\ // in a context where a fail probably shouldn't be handled either.
    \\.balign 0x80; B unhandled_vector // curr_el_spx_sync
    \\.balign 0x80; B unhandled_vector // curr_el_spx_irq
    \\.balign 0x80; B unhandled_vector // curr_el_spx_fiq
    \\.balign 0x80; B unhandled_vector // curr_el_spx_serror
    \\ // Userspace IRQs or syscalls
    \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch64_sync
    \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch64_irq
    \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch64_fiq
    \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch64_serror
    \\ // 32 bit Userspace IRQs or syscalls
    \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch32_sync
    \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch32_irq
    \\.balign 0x80; B interrupt_irq_stack     // lower_el_aarch32_fiq
    \\.balign 0x80; B interrupt_syscall_stack // lower_el_aarch32_serror
  );
}

extern const exception_vector_table: [0x800]u8;

pub fn install_vector_table() void {
  asm volatile(
    \\MSR VBAR_EL1, %[evt]
    :
    : [evt] "r" (&exception_vector_table)
  );
}

fn do_stack_call(frame: *InterruptFrame) void {
  const fun = @intToPtr(fn (*os.platform.InterruptFrame, usize) void, frame.x8);
  const ctx: usize = frame.x9;
  fun(frame, ctx);
}

export fn interrupt_handler(frame: *InterruptFrame) void {
  const esr = asm volatile("MRS %[esr], ESR_EL1" : [esr] "=r" (-> u64));

  const ec = (esr >> 26) & 0x3f;
  const iss = esr & 0x1ffffff;

  if(ec == 0b111100) {
    os.log("BRK instruction execution in AArch64 state\n", .{});
    os.platform.hang();
  }

  switch(ec) {
    else => @panic("Unknown EC!"),
    0b00000000 => @panic("Unknown reason in EC!"),
    0b00100101 => {
      const far = asm volatile("MRS %[esr], FAR_EL1" : [esr] "=r" (-> u64));
      const wnr = (iss >> 6) & 1;
      const dfsc = iss & 0x3f;

      // Assume present == !translation fault
      const present = (dfsc & 0b111100) != 0b000100;

      // addr: usize, present: bool, access: PageFaultAccess, frame: anytype
      os.platform.page_fault(far, present, if(wnr == 1) .Write else .Read, frame);
    },
    0b00100001 => @panic("Instruction fault without change in exception level"),
    0b00010101 => {
      // SVC instruction execution in AArch64 state
      // Figure out which call this is

      switch(@truncate(u16, iss)) {
        else => @panic("Unknown SVC"),

        'S' => do_stack_call(frame),
      }
    },
  }
}

pub fn set_interrupt_stack(int_stack: usize) void {
  const current_stack = asm volatile("MRS %[res], SPSel" : [res]"=r"(->u64));

  if(current_stack != 0) @panic("Cannot set interrupt stack while using it!");

  asm volatile(
    \\ MSR SPSel, #1
    \\ MOV SP, %[int_stack]
    \\ MSR SPSel, #0
    :
    : [int_stack] "r" (int_stack)
  );
}
