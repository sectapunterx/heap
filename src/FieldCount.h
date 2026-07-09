#pragma once

#include <cstddef>
#include <utility>

// Compile-time aggregate field count. Used to pin the shape of Task and CalEvent
// so that adding a field breaks the build of every serializer that has not been
// taught about it (HEAP-131), instead of silently dropping the field on save.
namespace heap::meta {

namespace detail {

// Converts to anything, so `T{Any{}, Any{}, …}` probes how many initialisers an
// aggregate accepts. Never defined: it is only ever used unevaluated.
struct Any {
  template<class T>
  constexpr operator T() const noexcept;  // NOLINT(google-explicit-constructor)
};

template<class T, class... Args>
constexpr std::size_t countFields() {
  if constexpr(requires { T{Args{}..., Any{}}; }) {
    return countFields<T, Args..., Any>();
  } else {
    return sizeof...(Args);
  }
}

}  // namespace detail

// Number of direct data members of the aggregate T.
template<class T>
constexpr std::size_t fieldCount() {
  return detail::countFields<T>();
}

}  // namespace heap::meta
