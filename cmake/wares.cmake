# wares.cmake: a small package manager for your favorite C/C++ build systems
cmake_minimum_required(VERSION 3.0.0 FATAL_ERROR)

set(CURRENT_WARES_VERSION 0.0.1-alpha)

function (wares_sync)
	execute_process(COMMAND wares sync -b)
endfunction()