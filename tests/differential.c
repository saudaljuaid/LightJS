#include "lightjs.h"
#include <stdio.h>
#include <string.h>

static double number(uint64_t bits) {
    double n;
    memcpy(&n, &bits, sizeof(n));
    return n;
}

static uint64_t bits(double n) {
    uint64_t raw;
    memcpy(&raw, &n, sizeof(raw));
    return raw;
}

int main(void) {
    uint64_t input[2];
    size_t count;
    while ((count = fread(input, 1, sizeof(input), stdin)) == sizeof(input)) {
        const uint64_t a = input[0], b = input[1];
        const double x = number(a), y = number(b);
        const uint64_t output[] = {
            lightjs_number(x), lightjs_number(y), lightjs_kind(a),
            bits(lightjs_to_number(a)), lightjs_to_boolean(a),
            (uint32_t)lightjs_to_int32(a), lightjs_strict_equal(a, b),
            lightjs_same_value(a, b), lightjs_same_value_zero(a, b),
            lightjs_number_add(x, y), lightjs_number_subtract(x, y),
            lightjs_number_multiply(x, y), lightjs_number_divide(x, y),
        };
        if (fwrite(output, sizeof(output), 1, stdout) != 1) return 1;
    }
    return count != 0 || ferror(stdin) || fflush(stdout) == EOF;
}
