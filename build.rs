use std::path::PathBuf;
use std::env;

// Example custom build script.
fn main() {

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());

    // Tell Cargo that if the given file changes, to rerun this build script.
    println!("cargo::rerun-if-changed=src/premake/luashim/luashim.c");
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();

    // Use the `cc` crate to build a C file and statically link it.
    let mut plugin_lib = cc::Build::new();
    plugin_lib.file("src/premake/luashim/luashim.c")
              .include("src/premake/luashim")
              .include("src/premake/lua/src");
    
    if target_os == "macos" {
        plugin_lib.define("LUA_USE_MACOSX", None);
    } else if target_os == "linux" {
        plugin_lib.define("LUA_USE_POSIX", None);
        plugin_lib.define("LUA_USE_DLOPEN", None);
    };

    plugin_lib.compile("luashim");

    // Tell cargo to look for shared libraries in the specified directory
    println!("cargo:rustc-link-search={}", out_path.canonicalize().unwrap().to_str().unwrap());

    // Tell cargo to tell rustc to link our `hello` library. Cargo will
    // automatically know it must look for a `libhello.a` file.
    println!("cargo:rustc-link-lib=luashim");

    // generate bindings for luashim
    // The bindgen::Builder is the main entry point
    // to bindgen, and lets you build up options for
    // the resulting bindings.
    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header("src/premake/luashim/luashim.h")
        // Add Lua to the include path
        .clang_arg("-I./src/premake/lua/src/")
        // Tell cargo to invalidate the built crate whenever any of the
        // included header files changed.
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        // Finish the builder and generate the bindings.
        .generate()
        // Unwrap the Result and panic on failure.
        .expect("Unable to generate bindings");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    bindings
        .write_to_file(out_path.join("luashim_bindings.rs"))
        .expect("Couldn't write bindings!");
}