<br />
<p align="center">
  <img src="./logos/wares_logo_hd.png" height="100" />
</p>
<br />

# A Hassle-free Package Manager for Your Favorite Build Tools

[![CI](https://github.com/lochnessdragon/wares/actions/workflows/ci.yml/badge.svg)](https://github.com/lochnessdragon/wares/actions/workflows/ci.yml)
[![GitHub tag (latest SemVer)](https://img.shields.io/github/v/tag/lochnessdragon/wares?label=Tag&logo=GitHub)](https://github.com/lochnessdragon/wares/releases)

Wares is a package manager compatible with all your favorite build tools. This includes both Premake and CMake in a ***very*** similar API.

## Design Philosophy

Wares was designed out of the need for a quick, painless, and easy way to install packages for premake and cmake projects. It was designed because the alternatives failed in one of the following ways:

1. No global cache directory
2. No easy install from a buildscript
3. No Premake/CMake support. (The former was particularly apparent)
4. Smooth build system integration

Our baseline philosophy is to be *fast, lightweight and a joy to use*.

## Features:
- Updater script
- Premake5!
- CMake!
- package lock file (`wares.lock`)
- global package cache! (WARES_CACHE environment + command line variable)

### Consume packages from:
- Github
- Gitlab
- Bitbucket
- Private repositories
- URLs
- Binary packages
- pkg-config

### Versioning!
- By release, tag, or commit
- Versioning follows the [cargo](https://doc.rust-lang.org/cargo/reference/resolver.html) versioning schema.

## Using

The first thing you will need to setup is a `wares.json` file. This specifies the various dependencies to download into your project. An example of this file is below:

```json
{
	"version": 0,
	"dependencies": [
		"gh:gabime/spdlog@^1.14.0"
	]
}
```

As you can see, this project depends on spdlog at or above version 1.14.0, but not 2.0.0. As of writing this document, only two versions are available that fit this requirement `1.14.0` and `1.14.1`. As such, wares would chose and download the `1.14.1` version from Github.

### Premake

#### Installation

To use wares with your premake file, simply add `premake/get_wares.lua` somewhere in your file directory. Then, in your top-level premake file, add: `include "PATH_TO_GET_WARES.LUA"`. `get_wares.lua` should automatically install `wares.lua` into your source tree and will keep it up to date.

#### Usage:

A (very simplified) example of using wares in a script is below (using the previous `dependencies.json` file):
```lua
wares = include("get_wares.lua")

local deps = wares.sync()

-- spdlog doesn't have a premake script, so we'll create a project for it
project "spdlog"
	kind "StaticLib"
	language "C++"
	cppdialect "C++20"

	files {
		deps["spdlog"] .. "/src/**.cpp",
		deps["spdlog"] .. "/include/**.h"
	}

	defines {
		"SPDLOG_COMPILED_LIB",
		"SPDLOG_USE_STD_FORMAT"
	}

	includedirs {
		deps["spdlog"] .. "/include/"
	}

project "App"
	kind "ConsoleApp"
	language "C++"

	files {
		"src/main.cpp"
	}

	-- link spdlog and add the include directories
	links { "spdlog" }
	includedirs { deps["spdlog"] .. "/include/" }
```

### CMake

#### Installation

To use wares with your cmake file, simply add `cmake/get_wares.cmake` somewhere in your file directory. Then, in your top-level premake file, add: `include(PATH_TO_GET_WARES.CMAKE)`. `get_wares.cmake` should automatically install `wares.lua` into your source tree and will keep it up to date.

#### Usage:

A (very simplified) example of using wares in a `CMakeLists.txt` file is below (using the previous `dependencies.json` file):
```cmake
cmake_minimum_required(VERSION 3.19)
include(get_wares.cmake)

project(App)

wares_sync()

add_executable(App src/main.cpp)

# spdlog is now included in the project, link it
target_link_libraries(App spdlog)
```

### CLI

Could:
 - install packages/update lockfile
 - clean cache
 - debug installation issues
 - add packages to the wares.json file
 - export dependencies to other formats (meson wrap, bdep, etc.)