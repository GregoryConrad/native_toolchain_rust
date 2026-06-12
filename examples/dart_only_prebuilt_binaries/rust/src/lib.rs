#[unsafe(no_mangle)]
pub extern "C" fn rust_multiply(a: i32, b: i32) -> i32 {
    a * b
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_rust_multiply() {
        assert_eq!(crate::rust_multiply(2, 3), 6);
    }
}
