#pragma once

#include "flo/ELF.hpp"
#include "flo/Florence.hpp"

namespace flo {
  struct KernelArguments {
    flo::ELF64Image const *elfImage;
    flo::PhysicalFreeList const *physFree;
    flo::VirtualAddress physBase;
    flo::VirtualAddress physEnd;
    u32 const *vgaX;
    u32 const *vgaY;
  };

  void printBacktrace();
  uptr deslide(uptr addr);
}
