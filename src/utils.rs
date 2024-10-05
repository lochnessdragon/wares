use std::path::PathBuf;
use std::env;
use std::num::ParseIntError;

// parses a hex value in a string, returning an array of u8 of a certain size
// if the templated argument N is smaller than value, the end will be truncated
// if the templated argument N is larger than value, the end of the array will by zero padded
pub fn parse_hex<const N: usize>(value: &str) -> Result<[u8; N], ParseIntError> {
	let mut result: [u8; N] = [0; N];

	for i in (0..value.len()).step_by(2) {
		// TODO: error handling if we exceed the size of result
		result[i / 2] = u8::from_str_radix(&value[i..i+2], 16)?;
	}

	Ok(result)
}

// constant variable for format_hex
const HEX_CHARS: &[u8; 16] = b"0123456789abcdef";

// formats a hex value to a string
pub fn format_hex<const N: usize>(hex: &[u8; N]) -> String {
	String::from_utf8(hex.iter().flat_map(|c| {
		let low = (c & 0xf) as usize;
		let high = ((c >> 4) & 0xf) as usize;
		[HEX_CHARS[high], HEX_CHARS[low]]

	}).collect()).expect("Programmer error in format_hex!")
}

// returns true if the str is a 40-length only 0-9, a-f character string
pub fn is_valid_hash(s: &str) -> bool {
	s.len() == 40 && s.as_bytes().iter().all(|c| { HEX_CHARS.contains(c) })
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

pub fn get_full_path<P: std::convert::AsRef<std::path::Path>>(path: P) -> Result<PathBuf, std::io::Error> {
	let full_path = std::fs::canonicalize(path)?;
	Ok(if full_path.to_str().unwrap().starts_with("\\\\?\\") {
		full_path.to_str().and_then(|s| s.get(4..)).map(PathBuf::from).unwrap_or(full_path)
	} else {
		full_path
	}) // consider using dunce crate instead
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn check_parse_hex() -> Result<(), ParseIntError> {
    	let result = parse_hex::<3>("32538B")?;
    	assert_eq!(result, [50, 83, 139]);
    	Ok(())
    }

    #[test]
    fn check_format_hex() {
    	let result = format_hex::<3>(&[89, 0, 241]);
    	assert_eq!(result, "5900f1");
    }

    #[test]
    fn check_filename_sanitization() {
        let result = sanitize_filename("test/file\\\\*sanitized?123<>\"|:");
        assert_eq!(result, "test_file___sanitized_123_____");
    }
}