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

### Premake

#### Installation
To use wares with your premake file, simply add `premake/get_wares.lua` somewhere in your file directory. Then, in your top-level premake file, add: `include "PATH_TO_GET_WARES.LUA"`. `get_wares.lua` should automatically install `wares.lua` into your source tree and will keep it up to date.

#### Usage:

An example of using wares in a script is below:
```lua
wares = include("get_wares.lua")

local spdlog = pm.depedency("gh:gabime/spdlog@v1.14.1", "./spdlog.lua")

project "App"
	kind "ConsoleApp"
	language "C++"

	links { "spdlog" }
	includedirs { spdlog.install_folder .. "include/" }
```
