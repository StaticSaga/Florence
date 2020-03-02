#include "flo/Memory.hpp"

#include "flo/Containers/RangeRandomizer.hpp"

#include "flo/Assert.hpp"
#include "flo/IO.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"

namespace flo::Memory {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[MEMORY]");

    flo::RangeRandomizer<flo::Paging::PageSize<1>> pageRanges;
  }
}

void *flo::getVirtualPages(uSz numPages) {
  return (void *)flo::Memory::pageRanges.get(numPages * flo::Paging::PageSize<1>, flo::random);
}

void flo::returnVirtualPages(void *at, uSz numPages) {
  flo::Memory::pageRanges.add((u64)at, numPages * flo::Paging::PageSize<1>);
}

void *flo::large_malloc(uSz size) {
  size = flo::Paging::alignPageUp<1, u64>(size + 8);
  auto numPages = size/flo::Paging::PageSize<1>;
  auto pageBase = flo::VirtualAddress{(u64)getVirtualPages(numPages)};

  assert(pageBase);

  flo::Paging::Permissions kernelRW;
  kernelRW.writeEnable = 1;
  kernelRW.allowUserAccess = 0;
  kernelRW.writethrough = 0;
  kernelRW.disableCache = 0;
  kernelRW.mapping.global = 0;
  kernelRW.mapping.executeDisable = 1;

  auto err = flo::Paging::map(pageBase, size, kernelRW);
  flo::checkMappingError(err, flo::Memory::pline, []() {
    assert_not_reached();
  });

  *getVirt<u64>(pageBase) = numPages;

  return (void *)(pageBase() + 8);
}