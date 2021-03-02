const std = @import("std");

fn read_msr(comptime T: type, msr_num: u32) T {
  std.debug.assert(T == u64);

  var low: u32 = undefined;
  var high: u32 = undefined;
  asm volatile("rdmsr" : [_]"={eax}"(low), [_]"={edx}"(high) : [_]"{ecx}"(msr_num));
  return (@as(u64, high) << 32) | @as(u64, low);
}

fn write_msr(comptime T: type, msr_num: u32, val: T) void {
  std.debug.assert(T == u64);

  const low = @truncate(u32, val);
  const high = @truncate(u32, val >> 32);
  asm volatile("wrmsr" :: [_]"{eax}"(low), [_]"{edx}"(high), [_]"{ecx}"(msr_num));
}

pub fn MSR(comptime T: type, comptime msr_num: u32) type {
  return struct {
    pub fn read() T {
      return read_msr(T, msr_num);
    }

    pub fn write(val: T) void {
      write_msr(T, msr_num, val);
    }
  };
}

pub fn ControlRegister(comptime T: type, comptime name: []const u8) type {
  return struct {
    pub fn read() T {
      return asm volatile(
        "mov %%" ++ name ++ ", %[out]"
        : [out]"=r"(-> T)
      );
    }

    pub fn write(val: T) void {
      asm volatile(
        "mov %[in], %%" ++ name
        :
        : [in]"r"(val)
      );
    }
  };
}

pub fn eflags() u64 {
  return asm volatile(
    \\pushfq
    \\cli
    \\pop %[flags]
    : [flags] "=r" (-> u64)
  );
}

pub fn fill_cpuid(res: anytype, leaf: u32) bool {
  if(leaf & 0x7FFFFFFF != 0) {
    if(!check_has_cpuid_leaf(leaf))
      return false;
  }

  var eax: u32 = undefined;
  var ebx: u32 = undefined;
  var edx: u32 = undefined;
  var ecx: u32 = undefined;

  asm volatile(
    \\cpuid
    : [eax] "={eax}" (eax)
    , [ebx] "={ebx}" (ebx)
    , [edx] "={edx}" (edx)
    , [ecx] "={ecx}" (ecx)
    : [leaf] "{eax}" (leaf)
  );
  return true;
}

pub fn check_has_cpuid_leaf(leaf: u32) bool {
  const max_func = cpuid(leaf & 0x80000000).?.eax;
  return leaf <= max_func;
}

const default_cpuid = struct {
  eax: u32,
  ebx: u32,
  edx: u32,
  ecx: u32,
};

pub fn cpuid(leaf: u32) ?default_cpuid {
  var result: default_cpuid = undefined;
  if(fill_cpuid(&result, leaf))
    return result;
  return null;
}