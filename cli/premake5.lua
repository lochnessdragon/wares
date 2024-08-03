workspace "WaresCLI"
	


project "wares"
	type "ConsoleApp"
	
	files {
		"source/*.cpp",
		"source/*.h"
	}

	include_dirs {
		"source/"
	}