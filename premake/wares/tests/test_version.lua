local suite = test.declare("wares_version")

function suite.versionFromStr()
	local semver = "1.5.3-alpha.rc1.2+build.150"
	test.isequal(Version:new(1, 5, 3, {"alpha", "rc1", "2"}, {"build", "150"}), Version:from_str(semver))
end