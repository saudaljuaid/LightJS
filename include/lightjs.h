#ifndef LIGHTJS_H
#define LIGHTJS_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Value bits are opaque and process-local. Invalid inputs yield kind 0,
   NaN for to_number, and 0 for conversions and comparisons. */
/* Requires binary64 doubles, round-to-nearest-even, gradual underflow,
   and masked FP exceptions. Calls do not configure these modes. */
enum lightjs_kind { LIGHTJS_NUMBER = 1, LIGHTJS_BOOLEAN, LIGHTJS_NULL, LIGHTJS_UNDEFINED };
uint64_t lightjs_number(double n);
uint64_t lightjs_boolean(uint32_t b);
uint64_t lightjs_null(void);
uint64_t lightjs_undefined(void);
uint32_t lightjs_kind(uint64_t value);
double lightjs_to_number(uint64_t value);
uint32_t lightjs_to_boolean(uint64_t value);
int32_t lightjs_to_int32(uint64_t value);
uint32_t lightjs_strict_equal(uint64_t a, uint64_t b);
uint32_t lightjs_same_value(uint64_t a, uint64_t b);
uint32_t lightjs_same_value_zero(uint64_t a, uint64_t b);
uint64_t lightjs_number_add(double a, double b);
uint64_t lightjs_number_subtract(double a, double b);
uint64_t lightjs_number_multiply(double a, double b);
uint64_t lightjs_number_divide(double a, double b);
#ifdef __cplusplus
}
#endif
#endif
