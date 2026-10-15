unsafe extern "C" {
    fn lightjs_number(n: f64) -> u64;
    fn lightjs_boolean(b: u32) -> u64;
    fn lightjs_null() -> u64;
    fn lightjs_undefined() -> u64;
    fn lightjs_kind(value: u64) -> u32;
    fn lightjs_to_number(value: u64) -> f64;
    fn lightjs_to_int32(value: u64) -> i32;
    fn lightjs_to_boolean(value: u64) -> u32;
    fn lightjs_strict_equal(a: u64, b: u64) -> u32;
    fn lightjs_same_value(a: u64, b: u64) -> u32;
    fn lightjs_same_value_zero(a: u64, b: u64) -> u32;
    fn lightjs_number_add(a: f64, b: f64) -> u64;
    fn lightjs_number_subtract(a: f64, b: f64) -> u64;
    fn lightjs_number_multiply(a: f64, b: f64) -> u64;
    fn lightjs_number_divide(a: f64, b: f64) -> u64;
}

#[test]
fn number_bits_cross_the_abi_without_losing_signed_zero() {
    for bits in [0, 1, 0x8000000000000000, 0x7fefffffffffffff, 0xfff0000000000000] {
        unsafe {
            let value = lightjs_number(f64::from_bits(bits));
            assert_eq!(lightjs_kind(value), 1);
            assert_eq!(lightjs_to_number(value).to_bits(), bits);
        }
    }
}

#[test]
fn conversions_and_equality_follow_javascript() {
    unsafe {
        let zero = lightjs_number(0.0);
        let negative_zero = lightjs_number(-0.0);
        let nan = lightjs_number(f64::from_bits(0xffffffffffffffff));
        assert!(lightjs_to_number(nan).is_nan());
        assert_eq!(lightjs_strict_equal(zero, negative_zero), 1);
        assert_eq!(lightjs_same_value(zero, negative_zero), 0);
        assert_eq!(lightjs_same_value_zero(zero, negative_zero), 1);
        assert_eq!(lightjs_strict_equal(nan, nan), 0);
        assert_eq!(lightjs_same_value(nan, nan), 1);
        assert_eq!(lightjs_same_value_zero(nan, nan), 1);
        assert_eq!(lightjs_to_boolean(nan), 0);
        assert_eq!(lightjs_to_int32(lightjs_number(-4294967297.0)), -1);
        assert_eq!(lightjs_to_number(lightjs_boolean(u32::MAX)), 1.0);
        assert_eq!(lightjs_to_number(lightjs_boolean(0)), 0.0);
        assert_eq!(lightjs_kind(lightjs_boolean(1)), 2);
        assert_eq!(lightjs_kind(lightjs_null()), 3);
        assert_eq!(lightjs_kind(lightjs_undefined()), 4);
        assert_eq!(lightjs_to_number(lightjs_null()), 0.0);
        assert!(lightjs_to_number(lightjs_undefined()).is_nan());
        assert_eq!(lightjs_strict_equal(lightjs_null(), lightjs_undefined()), 0);
    }
}

#[test]
fn nan_payloads_are_canonicalized_before_tagging() {
    for bits in [
        0x7ff0000000000001, 0x7ff7ffffffffffff, 0x7ff8000000000000,
        0x7fffffffffffffff, 0xfff0000000000001, 0xfff7ffffffffffff,
        0xfff8000000000000, 0xfff8000000000001, 0xfff8000000000002,
        0xfff8000000000003, 0xffffffffffffffff,
    ] {
        unsafe {
            let value = lightjs_number(std::hint::black_box(f64::from_bits(bits)));
            assert_eq!(value, 0x7ff8000000000000);
            assert_eq!(lightjs_kind(value), 1);
            assert_eq!(lightjs_to_number(value).to_bits(), 0x7ff8000000000000);
        }
    }
}

#[test]
fn invalid_raw_values_are_rejected_in_both_equality_arguments() {
    for bits in [
        0x7ff0000000000001, 0x7ff7ffffffffffff, 0x7ff8000000000001,
        0x7fffffffffffffff, 0xfff0000000000001, 0xfff7ffffffffffff,
        0xfff8000000000004, 0xffffffffffffffff,
    ] {
        unsafe {
            assert_eq!(lightjs_kind(bits), 0);
            assert_eq!(lightjs_to_number(bits).to_bits(), 0x7ff8000000000000);
            assert_eq!(lightjs_to_boolean(bits), 0);
            assert_eq!(lightjs_to_int32(bits), 0);
            for valid in [lightjs_number(0.0), lightjs_number(f64::NAN), lightjs_null()] {
                for (a, b) in [(bits, bits), (bits, valid), (valid, bits)] {
                    assert_eq!(lightjs_strict_equal(a, b), 0);
                    assert_eq!(lightjs_same_value(a, b), 0);
                    assert_eq!(lightjs_same_value_zero(a, b), 0);
                }
            }
        }
    }
}

#[test]
fn runtime_arithmetic_preserves_ieee_edges() {
    unsafe {
        let negative_zero = std::hint::black_box(-0.0);
        let tiny = std::hint::black_box(f64::from_bits(1));
        let normal = std::hint::black_box(f64::MIN_POSITIVE);
        let large = std::hint::black_box(9007199254740992.0);
        assert_eq!(lightjs_number_add(negative_zero, negative_zero), 1 << 63);
        assert_eq!(lightjs_number_subtract(negative_zero, 0.0), 1 << 63);
        assert_eq!(lightjs_number_add(large, 1.0), large.to_bits());
        assert_eq!(lightjs_number_multiply(tiny, 1.0), 1);
        assert_eq!(lightjs_number_divide(normal, 2.0), 1 << 51);
        assert_eq!(lightjs_number_divide(tiny, 2.0), 0);
        assert_eq!(lightjs_number_multiply(std::hint::black_box(f64::MAX), 2.0), f64::INFINITY.to_bits());
        assert_eq!(lightjs_number_divide(1.0, negative_zero), f64::NEG_INFINITY.to_bits());
        assert_eq!(lightjs_number_divide(0.0, negative_zero), 0x7ff8000000000000);
    }
}
