#pragma once

#include "Ints.hpp"
#include "flo/TypeTraits.hpp"
#include "flo/Limits.hpp"
#include "flo/Util.hpp"

namespace flo {
  u64 getRand();

  struct RandomDevice {
    using result_type = decltype(getRand());
    static constexpr result_type min() { return Limits<result_type>::min; }
    static constexpr result_type max() { return Limits<result_type>::max; }

    [[nodiscard]]
    auto operator()() {
      return getRand();
    }
  };

  inline RandomDevice random;

  template<typename T>
  struct UniformInts {
    static_assert(isIntegral<T>);
    constexpr UniformInts(T min, T max) {
      this->set(min, max);
    }

    constexpr void set(T min, T max) {
      this->min = min;
      this->max = max;
      update();
    }

    template<typename BitSource>
    T operator()(BitSource &bitSource) const {
      // We only support u64 bit sources for now
      static_assert(BitSource::min() == flo::Limits<u64>::min);
      static_assert(BitSource::max() == flo::Limits<u64>::max);

      while(1) if(auto val = bitSource() & bitmask; val <= max - min)
        return val + min;
    }

  private:
    /* Must set bitmask */
    constexpr void update() {
      // Special case where entire range of type is specified, we can't do max - min + 1 since it will overflow
      if(min == flo::Limits<T>::min && max == flo::Limits<T>::max)
        bitmask = ~T{0};
      else {
        auto desiredRange = max - min + 1;
        auto desiredBits = flo::Limits<T>::bits - flo::Util::countHighZeroes(desiredRange);

        if(desiredBits == flo::Limits<T>::bits)
          bitmask = ~T{0};
        else
          bitmask = (T{1} << desiredBits) - 1;
      }
    }

    T bitmask;
    T min;
    T max;
  };
}
