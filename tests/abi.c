#include "lightjs.h"
#include <math.h>

#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main(void) {
    uint64_t zero = lightjs_number(0.0), negzero = lightjs_number(-0.0);
    uint64_t nan = lightjs_number(NAN), truth = lightjs_boolean(42);
    CHECK(sizeof(zero) == 8 && lightjs_kind(zero) == LIGHTJS_NUMBER);
    CHECK(lightjs_kind(truth) == LIGHTJS_BOOLEAN && lightjs_to_boolean(truth) == 1);
    CHECK(lightjs_kind(lightjs_null()) == LIGHTJS_NULL);
    CHECK(lightjs_kind(lightjs_undefined()) == LIGHTJS_UNDEFINED);
    CHECK(lightjs_strict_equal(zero, negzero) && !lightjs_same_value(zero, negzero));
    CHECK(!lightjs_strict_equal(nan, nan) && lightjs_same_value(nan, nan));
    CHECK(lightjs_same_value_zero(zero, negzero));
    CHECK(signbit(lightjs_to_number(negzero)) && lightjs_to_int32(lightjs_number(4294967297.0)) == 1);
    CHECK(lightjs_to_number(lightjs_number_add(40.0, 2.0)) == 42.0);
    CHECK(lightjs_to_number(lightjs_number_subtract(44.0, 2.0)) == 42.0);
    CHECK(lightjs_to_number(lightjs_number_multiply(21.0, 2.0)) == 42.0);
    CHECK(lightjs_to_number(lightjs_number_divide(84.0, 2.0)) == 42.0);
    CHECK(lightjs_same_value(lightjs_number_add(-0.0, -0.0), negzero));
    CHECK(lightjs_same_value(lightjs_number_multiply(0.0, -1.0), negzero));
    CHECK(lightjs_to_number(lightjs_number_divide(1.0, -0.0)) == -INFINITY);
    CHECK(lightjs_same_value(lightjs_number_divide(0.0, 0.0), nan));
    CHECK(lightjs_same_value(lightjs_number_multiply(INFINITY, 0.0), nan));
    CHECK(lightjs_to_number(lightjs_number_multiply(0x1p-1074, 1.0)) == 0x1p-1074);
    CHECK(lightjs_to_number(lightjs_number_divide(0x1p-1022, 2.0)) == 0x1p-1023);
    CHECK(lightjs_to_number(lightjs_number_add(0x1p53, 1.0)) == 0x1p53);
    uint64_t invalid = UINT64_MAX;
    CHECK(lightjs_kind(invalid) == 0 && isnan(lightjs_to_number(invalid)));
    CHECK(lightjs_to_boolean(invalid) == 0 && lightjs_to_int32(invalid) == 0);
    CHECK(!lightjs_strict_equal(invalid, invalid) && !lightjs_same_value(invalid, invalid));
    CHECK(!lightjs_same_value_zero(invalid, invalid));
    return 0;
}
