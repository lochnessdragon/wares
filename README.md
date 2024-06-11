# Wares
A C/C++ package manager compatible with all your favorite build tools.

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
To use wares with your premake file, simply add `premake/get_wares.lua` somewhere in your file directory. Then, in your top-level premake file, add: `include "PATH.TO.GET.WARES.LUA"`. `get_wares.lua` should automatically install `wares.lua` into your source tree and will keep it up to date.

#### Usage:

To install a dependency, run: `pm.depdency("gh:gabime/spdlog@v1.14.1")` 
