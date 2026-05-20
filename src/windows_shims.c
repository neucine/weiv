#include <math.h>

// MSVC does not provide roundq; Zig std can still reference it on Windows.
long double roundq(long double x) {
  return roundl(x);
}
