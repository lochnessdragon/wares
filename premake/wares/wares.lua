-- wares.lua
-- the main wares Premake module file

 -- TODO: better error handling

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

local function alias(table, alias_name, original)
	table[alias_name] = {}
	setmetatable(table[alias_name], table[original])
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
	local output = handle:read("*a")
	local succeeded = handle:close() -- boolean
	return output, succeeded
end

-- returns the cache directory for the package manager
local function get_cache_dir()
	-- fall back order:
	-- (1) wares_cache command line option
	-- (2) WARES_CACHE environment variable
	-- (3) ./PackageCache
	return _OPTIONS["wares_cache"] or os.getenv("WARES_CACHE") or "PackageCache"
end

-- returns a list of versions from git ls-remote
local function get_github_versions(username, repository)
	local output, succeeded = run_command(string.format("git ls-remote --tags https://github.com/%s/%s.git", username, repository))

	local versions = {}

	if succeeded then
		--refs/tags/v<semver>
		local match_start = 0
		local match_end = 0
		local semver = nil
		while true do
			match_start, match_end, commit, semver = string.find(output, "(%w+)%s+refs/tags/v([%w%.%-]+)", match_end)
			if match_start == nil then break end
      versions[Version:from_str(semver)] = commit
		end
	else
		error(string.format("Failed to find github dependency %s/%s\n{CmdOut: %s}", username, repository, output))
	end

	return versions
end

-- returns the commit associated to a tag from git ls-remote
local function get_github_tag(username, repository, tag)
	local output, succeeded = run_command(string.format("git ls-remote --tags https://github.com/%s/%s.git %s", username, repository, tag))
	if succeeded then
		--refs/tags/<tag>
		local match_start, match_end, commit_hash = string.find(output, "(%w+)%s+refs/tags/" .. tag)
		if match_start == nil then error(string.format("Failed to find a tag matching %s for the github repository: %s/%s", tag, username, repository)) end
		return commit_hash
	else
		error(string.format("Failed to find github tag: %s in %s/%s\n{CmdOut: %s}", tag, username, repository, output))
	end
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
	-- type checking
	assert(type(semver_str) == "string", "semver_str is not a string")
  
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

-- VersionComparator "class"
-- follows rust's version matching rules
-- ex: ^1.14.0
-- a caret (^) prior to the semver indicates that it should allow everything up to a major change 
-- caret == "semver_compatible"
-- comparison type is one of:
-- ^  = SemVer compat <-- default
-- =  = equal
-- >= = greater than or equal
-- >  = greater than
-- <= = less than or equal
-- <  = less than
-- ~  = stricter SemVer compat
-- *  = any in the asterisk position *, 1.*, or 1.1.*

VersionComparator = { comparison_type = ">=", base_version = Version }
VersionComparator.__index = VersionComparator

VersionComparator.__tostring = function(self)
	return self.comparison_type .. tostring(self.base_version)
end

-- return true if this comparison matches a particular version, false otherwise
function VersionComparator:matches(version)
	if self.comparison_type == "=" then -- probably the easiest case
		return self.base_version == version
	elseif self.comparison_type == ">=" then
		return version >= self.base_version
	elseif self.comparison_type == ">" then
		return version > self.base_version
	elseif self.comparison_type == "<=" then
		return version <= self.base_version
	elseif self.comparison_type == "<" then
		return version < self.base_version
	elseif self.comparison_type == "^" then
		-- Semantic Versioning compatibility
		-- versions with pre-release fields are automatically incompatible
		if #version.pre_release > 0 then return false end
		-- as are versions with different majors
		if version.major ~= self.base_version.major then return false end
		-- any minor greater than base
		if version.minor == self.base_version.minor then
			-- any patch greater than or equal to base
			if version.patch >= self.base_version.patch then
				return true
			end
		elseif version.minor > self.base_version.minor then
			return true
		end
		return false
	elseif self.comparison_type == "~" then
		-- stricter compatibility range
		-- versions with pre-release fields are automatically incompatible
		if #version.pre_release > 0 then return false end
		-- as are versions with different majors
		if version.major ~= self.base_version.major then return false end
		-- and different minors
		if version.minor ~= self.base_version.minor then return false end
		-- only versions with greater than or equal to patches are allowed
		return version.patch >= self.base_version.patch
	elseif self.comparison_type == "*_major" then
		-- as long as it has no pre-releases, then it's compatible
		if #version.pre_release > 0 then return false else return true end
	elseif self.comparison_type == "*_minor" then
		-- versions with pre-release fields are automatically incompatible
		if #version.pre_release > 0 then return false end
		-- as are versions with different majors
		if version.major ~= self.base_version.major then return false end
		-- everything else is compatible
		return true
	elseif self.comparison_type == "*_patch" then
		-- versions with pre-release fields are automatically incompatible
		if #version.pre_release > 0 then return false end
		-- as are versions with different majors
		if version.major ~= self.base_version.major then return false end
		-- and different minors
		if version.minor ~= self.base_version.minor then return false end
		-- everything else is compatible
		return true
	end
end

function VersionComparator:new(o)
	setmetatable(o, self)

	return o
end

function VersionComparator:from_str(comparison_semver)
	-- read right to left, the version must start with one of:
	-- ^
	-- ~
	-- *
	-- <
	-- >
	-- <=
	-- >=
	-- =
	-- a digit
	if string.startswith(comparison_type, "^") then
		-- we've found a hat
		return VersionComparator:new({comparison_type = "^", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.starswith(comparison_type, "~") then
		-- we've found a tilde
		return VersionComparator:new({comparison_type = "~", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.starswith(comparison_type, "=") then
		-- we've found an equal sign
		return VersionComparator:new({comparison_type = "=", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.starswith(comparison_type, ">=") then
		-- we've found an >= sign
		return VersionComparator:new({comparison_type = ">=", base_version = Version:from_str(string.sub(comparison_semver, 3))})
	elseif string.starswith(comparison_type, "<=") then
		-- we've found an <= sign
		return VersionComparator:new({comparison_type = "<=", base_version = Version:from_str(string.sub(comparison_semver, 3))})
	elseif string.starswith(comparison_type, ">") then
		-- we've found a > sign
		return VersionComparator:new({comparison_type = ">", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.starswith(comparison_type, "<") then
		-- we've found a < sign
		return VersionComparator:new({comparison_type = "<", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.startswith(comparison_type, "*") then
		-- we've found an asterisk in the major position
		return VersionComparator:new({comparison_type = "*_major", base_version = Version:new(0, 0, 0)})
	elseif not string.contains(comparison_type, "*") then
		-- default
		return VersionComparator:new({comparison_type = "^", base_version = Version:from_str(comparison_semver)})
	end

	-- everything else has an asterisk at some point
	-- is the asterisk in the minor field?
	local match_start, match_end, maybe_major = string.find(comparison_semver, "(%d+).%*")
	if maybe_major ~= nil then
		return VersionComparator:new({comparison_type = "*_minor", base_version = Version:new(tonumber(maybe_major), 0, 0)})
	end

	-- is the asterisk in the patch field?
	local match_start, match_end, maybe_major, maybe_minor = string.find(comparison_semver, "(%d+).(%d+).%*")
	if maybe_major ~= nil then
		return VersionComparator:new({comparison_type = "*_patch", base_version = Version:new(tonumber(maybe_major), tonumber(maybe_minor), 0)})
	end

	error(string.format("Failed to parse version comparator: %s", comparison_semver))
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
-- pm stands for packaged module or package manager
pm = {}

pm.version = Version:new(0, 0, 1, "nightly")

-- _VERSION is a specialty premake-specific variable that contains the version
-- as a semver string 
pm._VERSION = tostring(pm.version)

-- providers
-- responsible for implementing the resolve and download
-- functions
pm.providers = {}
pm.providers["gh"] = {
	lock = function(dep_str)
		-- github strings look something alike to:
		-- username/repository@semver
		-- username/repository#tag
		-- username/repository <-- defaults to latest main branch commit
		-- username/repository/branch <-- latest commit on that branch
		-- username/repository!revision
		-- username and repository are required

		-- generate the lock information
		local dep = { type = "github" }

		-- try to read the username
		local match_start, match_end, username = string.find(dep_str, "([%w._]+)")
		dep.username = username

		-- try to read the repository
		local match_start, match_end, repository = string.find(dep_str, "([%w._]+)", match_end + 2)
		dep.repository = repository

		-- try all of: semver, tag, revision, and branch, choose one
		local next_char = dep_str:sub(match_end + 1, match_end + 1)
		if next_char == "@" then
			local semver = dep_str:sub(match_end + 2)
			-- find matching commit and version for this semver
			local version_comp = VersionComparator:from_str(semver)
			-- gather all versions from the git ls-remote
			local versions_commits = get_github_versions(username, repository)
			-- find the latest version that matches the comparison operator
			-- sort the versions
			local versions = {}
			for version in pairs(versions_commits) do table.insert(versions, version) end
			table.sort(versions)
			-- iterate through the versions in descending order
			for i = #versions,1,-1 do
				if version_comp:matches(versions[i]) then
					dep.version = tostring(versions[i])
					dep.commit = versions_commits[versions[i]]
					break
				end
			end
			if dep.version == nil then error("Failed to match " .. version_comp .. " with " .. username .. "/" .. repository) end
		elseif next_char == "#" then
			local tag = dep_str:sub(match_end + 2)
			dep.tag = tag
			-- lock the tag to a commit
			dep.commit = get_github_tag(username, repository, tag)
		elseif next_char == "!" then
			local rev = dep_str:sub(match_end + 2)
			dep.rev = rev
		elseif next_char == "/" then
			local branch = dep_str:sub(match_end + 2)
			dep.branch = branch
		end

		return dep
	end,

	install = function(lock_info)
		-- every github lock should have a username and a repository name
		-- a commit should be included with versioned, tagged, or reved github entrys
		-- if it doesn't include a commmit, but does include a branch, then it should follow that branch at the latest commit
		-- if it doesn't include a branch nor a commit, it should follow the main branch at the latest commit
		local install_folder = ""
		if lock_info.commit ~= nil then
			install_folder = path.getabsolute(get_cache_dir() .. "/gh-" .. lock_info.username .. "-" .. lock_info.repository .. "-" .. lock_info.commit)
		elseif lock_info.branch ~= nil then
			install_folder = path.getabsolute(get_cache_dir() .. "/gh-" .. lock_info.username .. "-" .. lock_info.repository .. "-" .. lock_info.branch .. "-latest")
		else
			install_folder = path.getabsolute(get_cache_dir() .. "/gh-" .. lock_info.username .. "-" .. lock_info.repository .. "-latest")
		end
		-- check if the folder exists, and therefore if the dependency is installed
		if not os.isdir(install_folder) then
			log.info(string.format("Installing github depedency: %s/%s to %s", lock_info.username, lock_info.repository, install_folder))
			local url = "https://github.com/" .. lock_info.username .. "/" .. lock_info.repository .. ".git"
			if lock_info.version ~= nil then
				os.executef("git clone --depth 1 --single-branch --branch v%s -- \"%s\" \"%s\"", lock_info.version, url, install_folder)
			elseif lock_info.tag ~= nil then
				os.executef("git clone --depth 1 --single-branch --branch %s -- \"%s\" \"%s\"", lock_info.tag, url, install_folder)
			elseif lock_info.branch ~= nil then
				os.executef("git clone --depth 1 --single-branch --branch %s  -- \"%s\" \"%s\"", lock_info.branch, url, install_folder)
			elseif lock_info.rev ~= nil then
				-- it's a little difficult to fetch a singular revision from git, so instead we:

				-- intialize an empty repository
				os.executef("git -C %s init", install_folder)
				-- add the remote url as the origin
				os.executef("git -C %s remote add origin %s", install_folder, url)
				-- fetch the specific revision
				os.executef("git -C %s fetch --depth 1 origin %s", install_folder, lock_info.rev)
				-- reset the branch to the revision of interest
				os.executef("git -C %s reset --hard FETCH_HEAD", install_folder)
			else
				-- latest commit
				os.executef("git clone --depth 1 --single-branch -- \"%s\" \"%s\"", url, install_folder)
			end
		elseif lock_info ~= nil then
			-- we may need to update the branch, check with git-fetch
			local output, success = run_command(string.format("git -C %s fetch --dry-run", install_folder))
			if success then
				if string.len(output) > 0 then
					-- needs an update
					local format_str = "" 
					if lock_info.branch ~= nil then format_str = "Updating %s/%s/%s..." else format_str = "Updating %s/%s..." end
					log.info(string.format(format_str, lock_info.username, lock_info.repository, lock_info.branch))
					run_command(sstring.format("git -C %s reset --hard", install_folder))
					run_command(sstring.format("git -C %s pull", install_folder))
				end
			else
				error("Failed to validate the integrity of %s/%s", lock_info.username, lock_info.repository)
			end
		end

		return install_folder
	end
}
pm.providers.gh.__index = pm.providers.gh

alias(pm.providers, "github", "gh")

-- updates the lockfile
pm.update = function()
	local manifest, err = json.decode(io.readfile("wares.json"))
	if err == nil then
		-- we ignore the version key for now
		-- create the lockfile table
		local lockfile_data = { version = 0, dependencies = {} }
		for k, v in ipairs(manifest.dependencies) do
			-- depedencies can only either be a string or a table with more information
			--assert(type(v) == "string" or type(v) == "table", "depedencies array can only consist of strings or tables!")
			if type(v) == "string" then 
				-- the first order of business is determining the provider for the string
				local match_start, match_end, provider_id = string.find(v, "(%a+)")
				if provider_id ~= nil then
					local provider = pm.providers[provider_id]
					if provider ~= nil then
						provider.lock(string.sub(v, match_end+2))
						table.insert(lockfile_data.dependencies, provider.lock(string.sub(v, match_end+2)))
					else
						error("Failed to find a provider for: " .. provider_id)
					end
				else
					error("Malformed depedency!")
				end
			elseif type(v) == "table" then

			else
				error("The dependencies array can only consist of strings or tables")
			end
		end

		-- write lockfile
		local lockfile_str, err = json.encode(lockfile_data)
		if err == nil then
			io.writefile("wares.lock", lockfile_str)
		else
			error(err)
		end
	else
		error(err)
	end
end

-- installs required dependencies
pm.install = function()
	local lockfile_data, err = json.decode(io.readfile("wares.lock"))
	if err == nil then
		-- ignore version key
		-- for every dependency, lookup the installation provider
		for i, depedency in ipairs(lockfile_data.dependencies) do
			local provider = pm.providers[depedency.type]
			if provider ~= nil then
				provider.install(depedency)
			else
				error("Failed to find a provider for: " .. table.tostring(depedency, 1))
			end
		end

	else
		error(err)
	end
end

-- updates the lockfile and installs the required dependencies
pm.sync = function()
	-- check to ensure a manifest file is present
	if not os.isfile("wares.json") then
		error("Failed to find a manifest file!")
	end

	-- if the lock file doesn't exist, it needs updating
	local update_lockfile = not os.isfile("wares.lock")

	if not update_lockfile then
		-- check if the lock file needs updating (the manifest file was updated more recently than the lock file)
		local manifest_stat = os.stat("wares.json")
		local lockfile_stat = os.stat("wares.lock")

		update_lockfile = lockfile_stat.mtime < manifest_stat.mtime
	end

	if update_lockfile then 
		log.info("Updating wares.lock...")
		pm.update() 
	end

	log.info("Installing dependencies...")
	pm.install()
end

-- responsible for:
-- updating the lockfile (if it needs it)
-- downloading/updating dependencies (again, if the need it)
-- generating information about where the source directories of those dependencies can be found.
pm.load_deps = function()
	pm.sync()
end

-- command line interface

-- option: wares_cache the folder that sources should be downloaded to
newoption {
   trigger = "wares_cache",
   value = "path",
   description = "Choose where wares' cache should be stored.",
}

-- action: wares-clean wipes the wares cache
newaction {
   trigger     = "wares-clean",
   description = "Cleans the wares cache",
   execute = function ()
      -- delete cache
      os.rmdir(get_cache_dir())
   end
}

-- action: wares-sync updates the lockfile if necessary and installs from the lockfile
newaction {
   trigger     = "wares-sync",
   description = "Updates the lockfile and installs dependencies",
   execute = pm.sync
}

log.info("Package Manager version " .. tostring(pm.version) .. " loaded!")
return pm