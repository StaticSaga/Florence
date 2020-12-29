#include "flo/Drivers/Gfx/IntelGraphics.hpp"

#include "flo/IO.hpp"

namespace flo::IntelGraphics {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[IntelGFX]");
  }
}

void flo::IntelGraphics::initialize(PCI::Reference const &ref, PCI::DeviceConfig const &device) {
  flo::IntelGraphics::pline("Got Intel VGA!");
}