-- wares.lua
-- the main wares Premake module file

-- wares 0.0.1

----------------------
-- PRIVATE INTERFACE
----------------------

----------------------
-- Console Operations
----------------------

-- Error Handling
local log = {}

log.info = function(msg)
	term.pushColor(term.infoColor)
	print("[info]: " .. msg)
	term.popColor()
end

log.warn = function(msg)
	term.pushColor(term.warningColor)
	print("[warn]: " .. msg)
	term.popColor()
end

log.error = function(msg)
	term.pushColor(term.errorColor)
	print("[error]: " .. msg)
	term.popColor()
end

local function consume_dot_separated_fields(str, start)
  local result = {}
	while true do
	  -- find 'next' pre-release field
    local match_start, match_end, field = string.find(str, "([%w-]+)", start)
    if match_start == nil then break end
    table.insert(result, field)
    start = match_end + 1
    -- check if there is a remaining field
    if string.sub(str, start, start) ~= "." then break end
	end
	
	return result, start
end

-- run a command and then get the output
local function run_command(cmd)
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	handle:close()
	return result
end

-- returns the cache directory for the package manager
local function get_cache_dir()
	return os.getenv("WARES_CACHE") or "PackageCache"
end

--------------------
-- PUBLIC INTERFACE
--------------------

-- Version "class"
Version = { major = 0, minor = 0, patch = 0, pre_release = {}, build_meta = {}}

-- Version meta methods
Version.__index = Version
Version.__tostring =  function(self)
	repr = string.format("%d.%d.%d", self.major, self.minor, self.patch)
	
	if #self.pre_release > 0 then
		repr = repr .. "-"
		for i = 1, #self.pre_release do 
		  repr = repr .. self.pre_release[i]
		  -- only place the dot between fields
		  if i ~= #self.pre_release then repr = repr .. "." end
		end
	end
	
	if #self.build_meta > 0 then 
		repr = repr .. "+"
		for i = 1, #self.build_meta do 
		  repr = repr .. self.build_meta[i]
		  if i ~= #self.build_meta then repr = repr .. "." end
		end
	end
	
	return repr
end

Version.__eq = function(ver1, ver2)
  local equal = ver1.major == ver2.major and ver1.minor == ver2.minor and ver1.patch == ver2.patch
  equal = equal and #ver1.pre_release == #ver2.pre_release 
  if equal then 
    -- we now know that both tables have the same length, we can loop through them, checking for equality
    for i = 1, #ver1.pre_release do
      equal = equal and ver1.pre_release[i] == ver2.pre_release[i]  
    end
  end
  
  return equal
end

Version.__lt = function(ver1, ver2)
    local less_than = ver1.major < ver2.major
    if less_than then return less_than end -- early out
    if ver1.major > ver2.major then return false end -- ver1 is actually greater than ver2
    
    less_than = ver1.minor < ver2.minor
    if less_than then return less_than end -- early out 
    if ver1.minor > ver2.minor then return false end -- ver1 is actually greater than ver2
    
    less_than = ver1.patch < ver2.patch
    if less_than then return less_than end -- early out 
    if ver1.patch > ver2.patch then return false end -- ver1 is actually greater than ver2
    
    -- check pre-release field(s)
    
    -- ver1 has no pre-release fields?
    if #ver1.pre_release == 0 and #ver2.pre_release > 0 then return true end
    -- ver2 has no pre-release fields?
    if #ver1.pre_release > 0 and #ver2.pre_release == 0 then return false end
    
    if #ver1.pre_release > 0 and #ver2.pre_release > 0 then 
      local field_count = math.min(#ver1.pre_release, #ver2.pre_release)  
      -- loop through all matching pre-release fields 
      for i = 1, field_count do 
        local ver1_is_number = tonumber(ver1.pre_release[i]) ~= nil
        local ver2_is_number = tonumber(ver2.pre_release[i]) ~= nil
        
        local pre_release_fields_equal = true
        
        if ver1_is_number and ver2_is_number then 
          -- identifiers consisting of only digits are compared numerically.
          local ver1_number = tonumber(ver1.pre_release[i])
          local ver2_number = tonumber(ver2.pre_release[i])
          if ver1_number < ver2_number then 
            less_than = true
            pre_release_fields_equal = false
            break
          elseif ver2_number < ver1_number then
            less_than = false
            pre_release_fields_equal = false
            break
          end
        elseif not ver1_is_number and not ver2_is_number then 
          -- identifiers with letters or hyphens are compared lexically in ASCII sort order.
          -- lua compares strings in alphabetical order
          if ver1.pre_release[i] < ver2.pre_release[i] then 
            less_than = true
            pre_release_fields_equal = false
            break
          elseif ver2.pre_release[i] < ver1.pre_release[i] then 
            less_than = false
            pre_release_fields_equal = false
            break
          end
        elseif ver1_is_number and not ver2_is_number then 
          -- numeric identifiers always have lower precedence than non-numeric identifiers.
          less_than = true
          pre_release_fields_equal = false
          break
        elseif not ver1_is_number and ver2_is_number then
          -- numeric identifiers always have lower precedence than non-numeric identifiers.
          less_than = false
          pre_release_fields_equal = false
          break
        end
      end
      
      -- a larger set of pre-release fields has a higher precedence than a smaller set, if all of the preceding identifiers are equal.
      if pre_release_fields_equal then 
        if #ver1.pre_release > #ver2.pre_release then 
          less_than = false
        elseif #ver2.pre_release > #ver1.pre_release then 
          less_than = true
        end
      end
    end
    
    return less_than
end

Version.__le = function(ver1, ver2)
    return ver1 == ver2 or ver1 < ver2
end

function Version:new(major, minor, patch, pre_release, build_meta)
	pre_release = pre_release or {}
	build_meta = build_meta or {}
	patch = patch or 0
	minor = minor or 0
	major = major or 0
	
	-- type checking
	assert(type(major) == "number", "major is not a number")
	assert(type(minor) == "number", "minor is not a number")
	assert(type(patch) == "number", "patch is not a number")
	assert(type(pre_release) == "table" or type(pre_release) == "string", "pre_release is not a table nor a string")
	assert(type(build_meta) == "table" or type(build_meta) == "string", "build_meta is not a table nor a string")
	
	-- convert string pre_release or build_meta to tables
	if type(pre_release) == "string" then 
	  pre_release = {pre_release}
	end
	if type(build_meta) == "string" then 
	  build_meta = {build_meta}
	end
	
	new_ver = { major = major, minor = minor, patch = patch, pre_release = pre_release, build_meta = build_meta }
	setmetatable(new_ver, self)

	return new_ver
end

function Version:from_str(semver_str)
  if type(semver_str) ~= "string" then 
    error("You must provide a string to Version:from_str")
    return
  end
  
  local match_start, match_end, major, minor, patch = string.find(semver_str, "(%d+).(%d+).(%d+)")
	local next_start = match_end
	
	major = tonumber(major)
	minor = tonumber(minor)
	patch = tonumber(patch)
	
	-- look for all of the pre-release field(s) following the major.minor.patch
	local pre_release_fields = {}
	match_start, match_end, hyphen = string.find(semver_str, "-", next_start)
	if match_start then
	  -- we now know that some pre-release info is attached
	  pre_release_fields, next_start = consume_dot_separated_fields(semver_str, match_end + 1)
	end
  
	-- look for all the build metadata field(s) following the -prerelease
	local build_metadata_fields = {}
	match_start, match_end, plus = string.find(semver_str, "%+", next_start)
	if match_start then 
	  -- we now know that some build metadata info is attached
	  build_metadata_fields, next_start = consume_dot_separated_fields(semver_str, match_end + 1)
	end
	
	return Version:new(major, minor, patch, pre_release_fields, build_metadata_fields)
end

-- DependencyInfo "class"
DependencyInfo = { name = "", include_dir = "", dependencies = {} }
DependencyInfo.__index = DependencyInfo

function DependencyInfo:new(o)
	o = o or {}
	setmetatable(o, self)

	return o
end

function DependencyInfo:link()
	links { self.name }
	includedirs { self.include_dir }

	for i, dependency in pairs(self.dependencies) do
		dependency:include()
	end
end

function DependencyInfo:include()
	includedirs { self.include_dir }
	for i, dependency in pairs(self.dependencies) do
		dependency:include()
	end
end

-- create a namespace for all the package manager's functions
pm = {}

pm.version = Version:new(0, 0, 1)
-- _VERSION is a specialty premake-specific variable that contains the version
-- as a semver string 
pm._VERSION = tostring(pm.version)

pm.github_dependency = function(username, repository_name, tag)
	local cache_dir = get_cache_dir()
	log.info("Github dependency: " .. username .. "/" .. repository_name .. " tag: " .. tag)
	
	local url = "https://github.com/" .. username .. "/" .. repository_name .. ".git"

	-- check if the remote repository and tag exists
	local git_query_result = run_command(string.format("git ls-remote %s %s", url, tag))
	if string.find(git_query_result, "fatal:") == nil then
		-- convert the tag to a commit
		local str_start, str_end, commit = string.find(git_query_result, "(%w+)\t[%a/]+" .. tag)
		local install_folder = path.getabsolute(cache_dir .. "/" .. username .. "-" .. repository_name .. "-" .. commit)

		-- check if the directory exists (and therefore if the repository is installed)
		if not os.isdir(install_folder) then
			-- clone the repository into the specific folder
			log.info("Installing to \"" ..  install_folder .. "\"")
			os.executef("git clone --depth 1 --branch %s -- \"%s\" \"%s\"", tag, url, install_folder)
		end

		return install_folder .. "/"
	else
		error("Failed to find the github tag " .. tag .. " for " .. username .. "/" .. repository_name)
	end
end

-- dependency: declares a dependency to be consumed by this project
-- dep_str: specifies how to find/install the package
-- Ex: gh:gambine/spdlog@v1.14.1
pm.dependency = function(dep_str, build_script)
	local dep_parts = string.explode(dep_str, ":")
	if dep_parts[1] == "gh" then 
		local username_info = string.explode(dep_parts[2], "/")
		local repo_version = string.explode(username_info[2], "@")
		local source_dir = pm.github_dependency(username_info[1], repo_version[1], repo_version[2])

		-- if we were provided a buildscript, try and run it!
		if build_script then
			if source_dir then
				return include(build_script)(source_dir)
			else
				error("Cannot run the provided build script as the package failed to download.")
			end
		end
		
		return source_dir
	end
end

log.info("Package Manager version " .. tostring(pm.version) .. " loaded!")
return pm