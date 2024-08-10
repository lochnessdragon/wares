// premake plugin
mod luashim;

use std::{collections::BTreeMap, path::PathBuf, str::Utf8Error};
use core::ffi::CStr;
use std::ptr;
use std::sync::OnceLock;
use std::ffi::CString;
use luashim::*;
use crate::{utils, SyncRunner};

#[derive(thiserror::Error, Debug)]
enum ReadLuaValueError {
	#[error("Type mismatch")]
	TypeMismatch,
	#[error("Utf-8 Error")]
	Utf8Error(#[from] Utf8Error)
}

unsafe fn print_lua_stack_top(state: *mut lua_State, count: u32) {
	println!("--STACK TOP--");
	for i in 1..=count {
		println!("{}: {}", i, CStr::from_ptr(lua_typename(state, lua_type(state, -(i as i32)))).to_string_lossy());
	}
}

unsafe fn read_lua_string_array(state: *mut lua_State, stack_index: i32) -> Result<Vec<String>, ReadLuaValueError> {
	if lua_type(state, stack_index) != LUA_TTABLE as i32 {
		println!("read_string_array: Not a table!");
		return Err(ReadLuaValueError::TypeMismatch);
	}

	let size = luaL_len(state, stack_index);

	let mut result: Vec<String> = Vec::with_capacity(size as usize);

	// in lua, arrays start at one
	for i in 1..=size {
		lua_rawgeti(state, stack_index, i);
		let str_ptr = lua_tolstring(state, -1, ptr::null_mut());
		if str_ptr == ptr::null() {
			return Err(ReadLuaValueError::TypeMismatch);
		}
		result.push(CStr::from_ptr(str_ptr).to_str()?.to_owned());
		lua_settop(state, -2); // "pop" value
	}

	Ok(result)
}

unsafe fn read_lua_string_map(state: *mut lua_State, stack_index: i32) -> Result<BTreeMap<String, String>, ReadLuaValueError> {
	assert!(stack_index < 0);
	if lua_type(state, stack_index) != LUA_TTABLE as i32 {
		return Err(ReadLuaValueError::TypeMismatch);
	}

	let mut result: BTreeMap<String, String> = BTreeMap::new();
	// push the first key
	lua_pushnil(state);
	// table is now at stack_index - 1 (assuming originally defined from the top of the stack)
	while lua_next(state, stack_index - 1) != 0 {
		// key is now at index -2 and value is at index -1
		if lua_isstring(state, -2) == 0 {
			// key needs to be a string
			return Err(ReadLuaValueError::TypeMismatch);
		}

		if lua_isstring(state, -1) == 0 {
			// value needs to be a string
			return Err(ReadLuaValueError::TypeMismatch);
		}

		// retreive the key
		let key_ptr = lua_tolstring(state, -2, ptr::null_mut());
		let key = CStr::from_ptr(key_ptr).to_str()?.to_owned();

		// retreive the value
		let value_ptr = lua_tolstring(state, -1, ptr::null_mut());
		let value = CStr::from_ptr(value_ptr).to_str()?.to_owned();

		result.insert(key, value);

		lua_settop(state, -2); // "pop" the value, keeping the key for the next iteration
	}
	// the key should be popped here from the call to lua_next

	Ok(result)
}

// stack:
// 1. path to the root folder
// 2. path to the current folder
// 3. path to the cache folder? (if nil, allow default cache behavior) 
// 4. an array containing the extra deps as a string
// 5. a table containing the overriden deps and their folder names
// returns a table of the dependency names mapped to their folders
pub unsafe extern "C" fn premake_sync(state: *mut lua_State) -> i32 {
	static mut TIMES_CALLED: OnceLock<u64> = OnceLock::new();

	let first = TIMES_CALLED.get_or_init(|| 0) == &0;

	// print_lua_stack_top(state, 5);

	// lua pushes arguments in right to left order, this means that the first argument is on the bottom of the stack
	// read in lock folder name
	let root_str_ptr = lua_tolstring(state, -5, ptr::null_mut());
	if root_str_ptr == ptr::null() {
		lua_pushstring(state, CString::new("The first argument must be a string specifying the folder that wares.lock is in!").unwrap().as_ptr());
		return 1; // 1 return value
	}

	let mut lock_file = PathBuf::from(match CStr::from_ptr(root_str_ptr).to_str() {
		Ok(path) => path,
		Err(utf8_error) => {
			lua_pushstring(state, CString::new(format!("{utf8_error}")).unwrap().as_ptr());
			return 1;
		}
	});

	lock_file.push("wares");
	lock_file.set_extension("lock");

	// read in manifest folder name
	let current_str_ptr = lua_tolstring(state, -4, ptr::null_mut());
	if current_str_ptr == ptr::null() {
		lua_pushstring(state, CString::new("The second argument must be a string specifying the folder that wares.toml is in!").unwrap().as_ptr());
		return 1; // 1 return value
	}

	let mut manifest_file = PathBuf::from(match CStr::from_ptr(current_str_ptr).to_str() {
		Ok(path) => path,
		Err(utf8_error) => {
			lua_pushstring(state, CString::new(format!("{utf8_error}")).unwrap().as_ptr());
			return 1;
		}
	});

	manifest_file.push("wares");
	manifest_file.set_extension("toml");

	// read in cache folder
	let cache_folder = if lua_isstring(state, -3) > 0 {
		let cache_folder_ptr = lua_tolstring(state, -3, ptr::null_mut());
		PathBuf::from(match CStr::from_ptr(root_str_ptr).to_str() {
			Ok(path) => path,
			Err(utf8_error) => {
				lua_pushstring(state, CString::new(format!("{utf8_error}")).unwrap().as_ptr());
				return 1;
			}
		})
	} else {
		utils::cache_dir_fallback()
	};

	// read in extra deps array
	let extra_deps: Vec<String> = match read_lua_string_array(state, -2) {
		Ok(value) => value,
		Err(ReadLuaValueError::TypeMismatch) => {
			lua_pushstring(state, CString::new("The extra_deps array must contain only strings").unwrap().as_ptr());
			return 1;
		},
		Err(ReadLuaValueError::Utf8Error(utf8_error)) => {
			lua_pushstring(state, CString::new(format!("{utf8_error}")).unwrap().as_ptr());
			return 1;
		}
	};

	// read in overrides map
	let overrides: BTreeMap<String, String> = match read_lua_string_map(state, -1){
		Ok(value) => value,
		Err(ReadLuaValueError::TypeMismatch) => {
			lua_pushstring(state, CString::new("The overrides table must be a map of strings to strings").unwrap().as_ptr());
			return 1;
		},
		Err(ReadLuaValueError::Utf8Error(utf8_error)) => {
			lua_pushstring(state, CString::new(format!("{utf8_error}")).unwrap().as_ptr());
			return 1;
		}
	};
	println!("Manifest: {}", manifest_file.display());
	println!("Lock: {}", lock_file.display());
	println!("Cache: {}", cache_folder.display());
	println!("Extra dependencies: {:#?}", extra_deps);
	println!("Overrides: {:#?}", overrides);

	static mut UPDATED_LAST: OnceLock<bool> = OnceLock::new();
	UPDATED_LAST.get_or_init(|| false);

	// force an update if we updated the last time
	let force_update = !first && *UPDATED_LAST.get().expect("OnceLock failed us!");

	let mut runner = SyncRunner::build(&extra_deps, &manifest_file, &lock_file, &cache_folder, force_update, overrides, first);

	if first && runner.needs_update() {
		*UPDATED_LAST.get_mut().expect("OnceLock failed us!") = true;
	}

	match runner.sync() {
		Ok(deps) => {
			// convert deps map to lua
			lua_createtable(state, 0, deps.keys().len() as i32);
			for (dep_name, install_folder) in deps {
				// push the key
				let key = match CString::new(dep_name) {
					Ok(value) => value,
					Err(err) => {
						lua_pushstring(state, CString::new(format!("{err}")).unwrap().as_ptr());
						return 1;
					}
				};
				lua_pushstring(state, key.as_ptr());

				// push the value
				let value = match CString::new(install_folder) {
					Ok(value) => value,
					Err(err) => {
						lua_pushstring(state, CString::new(format!("{err}")).unwrap().as_ptr());
						return 1;
					}
				};
				lua_pushstring(state, value.as_ptr());

				// place that in the table
				lua_settable(state, -3);
			}
		},
		Err(error) => {
			let error_value = format!("{}", error);
			let error_cstr = CString::new(error_value).unwrap();
			lua_pushstring(state, error_cstr.as_ptr());
		}
	}

	*TIMES_CALLED.get_mut().expect("OnceLock failed us!") += 1;
	// 1 return value
	return 1;
}

// premake plugin
#[no_mangle] // required for the plugin to be detected in the dll
pub unsafe extern "C" fn luaopen_wares_native(state: *mut lua_State) -> i32 {
	let sync_str = CString::new("sync_backend").unwrap();
	let empty_str = CString::new("").unwrap();

	let wares_functions = Box::new([
			luaL_Reg { name: sync_str.as_ptr() as *const i8,  func: Some(premake_sync) },
			luaL_Reg { name: ptr::null(), func: None }
	]);

	let wares_string = CString::new("wares_native").unwrap();
	shimInitialize(state);
	luaL_register(state, wares_string.as_ptr() as *const i8, Box::into_raw(wares_functions) as *const luaL_Reg);

	println!("Wares v0.0.1-nightly initialized");
	0
}