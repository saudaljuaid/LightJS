#include "lightjs.h"
#include <math.h>
#include <string.h>

static double number_from_bits(uint64_t bits) {
    double number;
    memcpy(&number, &bits, sizeof(number));
    return number;
}

static uint64_t number_bits(double number) {
    uint64_t bits;
    memcpy(&bits, &number, sizeof(bits));
    return bits;
}

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
    const uint64_t nan_payloads[] = {
        UINT64_C(0x7ff0000000000001), UINT64_C(0x7ff7ffffffffffff),
        UINT64_C(0x7ff8000000000000), UINT64_C(0x7fffffffffffffff),
        UINT64_C(0xfff0000000000001), UINT64_C(0xfff7ffffffffffff),
        UINT64_C(0xfff8000000000000), UINT64_C(0xfff8000000000001),
        UINT64_C(0xfff8000000000002), UINT64_C(0xfff8000000000003), UINT64_MAX,
    };
    for (size_t i = 0; i < sizeof(nan_payloads) / sizeof(nan_payloads[0]); i++) {
        volatile double input = number_from_bits(nan_payloads[i]);
        uint64_t value = lightjs_number(input);
        CHECK(value == UINT64_C(0x7ff8000000000000));
        CHECK(lightjs_kind(value) == LIGHTJS_NUMBER);
        CHECK(number_bits(lightjs_to_number(value)) == UINT64_C(0x7ff8000000000000));
    }
    const uint64_t invalid_values[] = {
        UINT64_C(0x7ff0000000000001), UINT64_C(0x7ff7ffffffffffff),
        UINT64_C(0x7ff8000000000001), UINT64_C(0x7fffffffffffffff),
        UINT64_C(0xfff0000000000001), UINT64_C(0xfff7ffffffffffff),
        UINT64_C(0xfff8000000000004), UINT64_MAX,
    };
    for (size_t i = 0; i < sizeof(invalid_values) / sizeof(invalid_values[0]); i++) {
        uint64_t invalid = invalid_values[i];
        CHECK(lightjs_kind(invalid) == 0 && isnan(lightjs_to_number(invalid)));
        CHECK(lightjs_to_boolean(invalid) == 0 && lightjs_to_int32(invalid) == 0);
        CHECK(!lightjs_strict_equal(invalid, invalid) && !lightjs_same_value(invalid, invalid));
        CHECK(!lightjs_same_value_zero(invalid, invalid));
        CHECK(!lightjs_strict_equal(invalid, zero) && !lightjs_strict_equal(zero, invalid));
        CHECK(!lightjs_same_value(invalid, nan) && !lightjs_same_value(nan, invalid));
        CHECK(!lightjs_same_value_zero(invalid, nan) && !lightjs_same_value_zero(nan, invalid));
    }
    return 0;
}
