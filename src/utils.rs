use std::path::PathBuf;
use std::env;
use std::num::ParseIntError;

// parses a hex value in a string, returning an array of u8 of a certain size
pub fn parse_hex<const N: usize>(value: &str) -> Result<[u8; N], ParseIntError> {
	let mut result : [u8; N] = [0; N];

	for i in (0..value.len()).step_by(2) {
		// TODO: error handling if we exceed the size of result
		result[i] = u8::from_str_radix(&value[i..i+2], 16)?
	}

	Ok(result)
}

pub fn sanitize_filename<S: AsRef<str>>(filename: S) -> String {
	let str_ref = filename.as_ref();

	str_ref.chars()
		.map(|x| match x {
			// 1F == 31
			'\x00'..='\x1F' | '/' | '\\' |
			 '<' | '>' | ':' | '"' | '|' |
			 '?' | '*' => '_', // invalid characters on linux and windows
			_ => x
		}).collect()
}

// Provide a fallback for the wares cache directory
pub fn cache_dir_fallback() -> PathBuf {
	PathBuf::from(env::var("WARES_CACHE").unwrap_or(String::from("./.wares_cache")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn check_filename_sanitization() {
        let result = sanitize_filename("test/file\\\\*sanitized?123<>\"|:");
        assert_eq!(result, "test_file___sanitized_123_____");
    }
}