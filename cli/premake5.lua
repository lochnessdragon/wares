workspace "WaresCLI"
	platforms { "x64" }
	configurations { "Debug", "Release" }


project "wares"
	type "ConsoleApp"
	
	files {
		"source/*.cpp",
		"source/*.h"
	}

	include_dirs {
		"source/"
	}