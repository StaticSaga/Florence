#include "flo/Drivers/Gfx/GenericVGA.hpp"

#include "flo/IO.hpp"

namespace flo::GenericVGA {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[GVGA]");
  }
}

void flo::GenericVGA::initialize(PCI::Reference const &ref, PCI::Identifier const &ident) {
  flo::GenericVGA::pline("Got generic VGA at ", ref.bus(), ":", ref.slot(), ".", ref.function());
}
