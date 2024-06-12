<br />
<p align="center">
  <img src="./logos/wares_logo_hd.png" height="100" />
</p>
<br />

# Wares

[![CI](https://github.com/lochnessdragon/wares/actions/workflows/ci.yml/badge.svg)](https://github.com/lochnessdragon/wares/actions/workflows/ci.yml)
[![GitHub tag (latest SemVer)](https://img.shields.io/github/v/tag/lochnessdragon/wares?label=Tag&logo=GitHub)](https://github.com/lochnessdragon/wares/releases)

A C/C++ package manager compatible with all your favorite build tools.

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
- package.lock
- global package cache!

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

## Using

The first thing you will need to setup is a `wares.json` file. This specifies the various depedencies to download into your project. An example of this file is below:

```json
{
	"version": 0,
	"dependencies": [
		"gh:gabime/spdlog@^1.14.0"
	]
}
```

As you can see, this project depends on spdlog at or above version 1.14.0, but not 2.0.0.

### Premake

#### Installation
To use wares with your premake file, simply add `premake/get_wares.lua` somewhere in your file directory. Then, in your top-level premake file, add: `include "PATH_TO_GET_WARES.LUA"`. `get_wares.lua` should automatically install `wares.lua` into your source tree and will keep it up to date.

#### Usage:

A (very simplified) example of using wares in a script is below (using the previous `dependencies.json` file):
```lua
wares = include("get_wares.lua")

local deps = wares.sync()

project "App"
	kind "ConsoleApp"
	language "C++"

	links { "spdlog" }
	includedirs { deps["spdlog"] .. "/include/" }
```
