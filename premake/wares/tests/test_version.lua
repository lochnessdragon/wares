local suite = test.declare("wares_version")

function suite.versionFromStr()
	local semver = "1.5.3-alpha.rc1.2+build.150"
	test.isequal(Version:new(1, 5, 3, {"alpha", "rc1", "2"}, {"build", "150"}), Version:from_str(semver))
end

function suite.versionToStr()
	local version = Version:new(3, 5, 1, "beta", "sha256")
	test.isequal(tostring(version), "3.5.1-beta+sha256")
end

function suite.versionEqual()
	
end

function suite.versionLessThan()

end

function suite.versionLessThanEqualTo()

end