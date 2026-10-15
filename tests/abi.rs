unsafe extern "C" {
    fn lightjs_number(n: f64) -> u64;
    fn lightjs_boolean(b: u32) -> u64;
    fn lightjs_to_number(value: u64) -> f64;
    fn lightjs_to_int32(value: u64) -> i32;
    fn lightjs_to_boolean(value: u64) -> u32;
    fn lightjs_strict_equal(a: u64, b: u64) -> u32;
    fn lightjs_same_value(a: u64, b: u64) -> u32;
}

#[test]
fn number_bits_cross_the_abi_without_losing_signed_zero() {
    for bits in [0, 1, 0x8000000000000000, 0x7fefffffffffffff, 0xfff0000000000000] {
        unsafe {
            let value = lightjs_number(f64::from_bits(bits));
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
        assert_eq!(lightjs_strict_equal(nan, nan), 0);
        assert_eq!(lightjs_same_value(nan, nan), 1);
        assert_eq!(lightjs_to_boolean(nan), 0);
        assert_eq!(lightjs_to_int32(lightjs_number(-4294967297.0)), -1);
        assert_eq!(lightjs_to_number(lightjs_boolean(1)), 1.0);
        assert_eq!(lightjs_to_number(lightjs_boolean(0)), 0.0);
    }
}
