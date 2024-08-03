-- wares.lua
-- should we instead make a binary module?
-- Pros:
--  1. Support .toml
--  2. One codebase for both Premake and a cli
--  3. No need to write lua
-- Cons:
--  1. No lua
--  2. Still have to write a CMake script
--  3. Have to distribute different versions for different operating systems
--  4. At that point, just have an external binary that is called with something like os.process
-- the main wares Premake module file
-- TODO: better error handling

----------------------
-- PRIVATE INTERFACE
----------------------

----------------------
-- Console Operations
----------------------

-- Logging
local log = include "log.lua"
local array = include "array.lua"
local utils = include "utils.lua"

-- adds another entry on a table that points to the same object
local function alias(table, alias_name, original)
	table[alias_name] = {}
	setmetatable(table[alias_name], table[original])
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

-- returns the absolute path to the lockfile
local function get_lockfile_path()
	return _MAIN_SCRIPT_DIR .. "/wares.lock"
end

-- returns a list of versions from git ls-remote
local function get_git_versions(url, error_message)
	local output, succeeded = run_command(string.format("git ls-remote --tags %s", url))

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
		error(string.format("%s\n{CmdOut: %s}", error_message, output))
	end

	return versions
end

-- provider specific endpoints here
local function get_github_versions(username, repository)
	return get_git_versions(string.format("https://github.com/%s/%s.git", username, repository), string.format("Failed to find github dependency %s/%s", username, repository))
end

local function get_gitlab_versions(username, repository)
	return get_git_versions(string.format("https://gitlab.com/%s/%s.git", username, repository), string.format("Failed to find gitlab dependency %s/%s", username, repository))
end

local function get_bitbucket_versions(username, repository)
	return get_git_versions(string.format("https://bitbucket.org/%s/%s.git", username, repository), string.format("Failed to find bitbucket dependency %s/%s", username, repository))
end

-- returns the commit associated to a tag from git ls-remote
local function get_git_tag(url, tag, human_readable_identifier)
	local output, succeeded = run_command(string.format("git ls-remote --tags %s %s", url, tag))
	if succeeded then
		--refs/tags/<tag>
		local match_start, match_end, commit_hash = string.find(output, "(%w+)%s+refs/tags/" .. utils.regex_escape(tag))
		if match_start == nil then error(string.format("Failed to find a tag matching %s for the %s", tag, human_readable_identifier)) end
		return commit_hash
	else
		error(string.format("Failed to find tag: %s in the %s\n{CmdOut: %s}", tag, human_readable_identifier, output))
	end
end

-- provider specific endpoints here
local function get_github_tag(username, repository, tag)
	return get_git_tag(string.format("https://github.com/%s/%s.git", username, repository), tag, string.format("github repository: %s/%s", username, repository))
end

local function get_gitlab_tag(username, repository, tag)
	return get_git_tag(string.format("https://gitlab.com/%s/%s.git", username, repository), tag, string.format("gitlab repository: %s/%s", username, repository))
end

local function get_bitbucket_tag(username, repository, tag)
	return get_git_tag(string.format("https://bitbucket.org/%s/%s.git", username, repository), tag, string.format("bitbucket repository: %s/%s", username, repository))
end

--------------------
-- PUBLIC INTERFACE
--------------------

include "version.lua"

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

-- Git
pm.providers["git"] = {
	lock = function(dep_str)
		-- git strings look something alike to:
		-- url@semver
		-- url#tag
		-- url/branch <-- latest commit on that branch
		-- url!revision
		-- url is required

		-- default lock information
		local dep = { type = "git" }

		-- try to match the url (must have https:// at the start and .git at the end)
		local match_start, match_end, url = string.find(dep_str, "(https://[%w%._/]+.git)")
		if match_start == nil then
			-- no match found
			error("Failed to find a url in the git dependency: " .. dep_str)
		end
		dep.url = url

	end,

	update = function(lock_info)
	end
}
pm.providers.git.__index = pm.providers.git

-- locks a dependency using a dep_str that looks similar to the github dependency strings
local function github_like_lock(dep_str, provider_name, version_callback, tag_callback)
	-- github-like strings look something alike to:
	-- username/repository@semver
	-- username/repository#tag
	-- username/repository <-- defaults to latest main branch commit
	-- username/repository/branch <-- latest commit on that branch
	-- username/repository!revision
	-- username and repository are required
	local lock_info = {}
	-- try to read the username
	local match_start, match_end, username = string.find(dep_str, "([%w._%-]+)")
	if match_start == nil then error("Failed to find a username in the ".. provider_name .. " dependency: " .. dep_str)	end
	lock_info.username = username

	-- try to read the repository
	local match_start, match_end, repository = string.find(dep_str, "([%w._%-]+)", match_end + 2)
	if match_start == nil then error("Failed to find a repository in the ".. provider_name .. " dependency: " .. dep_str)	end
	lock_info.repository = repository

	-- try all of: semver, tag, revision, and branch, choose one
	local next_char = dep_str:sub(match_end + 1, match_end + 1)
	if next_char == "@" then
		local semver = dep_str:sub(match_end + 2)
		-- find matching commit and version for this semver
		local version_comp = VersionComparator:from_str(semver)
		-- gather all versions from the git ls-remote
		local versions_commits = version_callback(username, repository)
		-- find the latest version that matches the comparison operator
		-- sort the versions
		local versions = {}
		for version in pairs(versions_commits) do table.insert(versions, version) end
		table.sort(versions)
		-- iterate through the versions in descending order
		for i = #versions,1,-1 do
			if version_comp:matches(versions[i]) then
				lock_info.version = tostring(versions[i])
				lock_info.commit = versions_commits[versions[i]]
				break
			end
		end
		if lock_info.version == nil then error("Failed to match " .. tostring(version_comp).. " with " .. username .. "/" .. repository) end
	elseif next_char == "#" then
		local tag = dep_str:sub(match_end + 2)
		lock_info.tag = tag
		-- lock the tag to a commit
		lock_info.commit = tag_callback(username, repository, tag)
	elseif next_char == "!" then
		local rev = dep_str:sub(match_end + 2)
		lock_info.rev = rev
	elseif next_char == "/" then
		local branch = dep_str:sub(match_end + 2)
		lock_info.branch = branch
	end
	-- TODO: implement recursively reading manifest.json
	return lock_info
end

-- installs a dependency that uses a table that looks similar to the github dependency install tables
local function github_like_install(lock_info, unique_id, url_pattern)
	-- every github-like lock info should have a username, a repository name, and a type
	-- a commit should be included with versioned, tagged, or reved github entrys
	-- if it doesn't include a commmit, but does include a branch, then it should follow that branch at the latest commit
	-- if it doesn't include a branch nor a commit, it should follow the main branch at the latest commit
	local install_folder = ""
	if lock_info.commit ~= nil then
		install_folder = path.getabsolute(get_cache_dir() .. "/" .. unique_id .. "-" .. lock_info.username .. "-" .. lock_info.repository .. "-" .. lock_info.commit)
	elseif lock_info.branch ~= nil then
		install_folder = path.getabsolute(get_cache_dir() .. "/" .. unique_id .. "-" .. lock_info.username .. "-" .. lock_info.repository .. "-" .. lock_info.branch .. "-latest")
	else
		install_folder = path.getabsolute(get_cache_dir() .. "/" .. unique_id .. "-" .. lock_info.username .. "-" .. lock_info.repository .. "-latest")
	end
	-- check if the folder exists, and therefore if the dependency is installed
	if not os.isdir(install_folder) then
		log.info(string.format("Installing %s depedency: %s/%s to %s", lock_info.type, lock_info.username, lock_info.repository, install_folder))
		local url = string.format(url_pattern, lock_info.username, lock_info.repository)
		
		if lock_info.version ~= nil then
			os.executef("git clone --depth 1 --single-branch --branch v%s -- \"%s\" \"%s\"", lock_info.version, url, install_folder)
		elseif lock_info.tag ~= nil then
			os.executef("git clone --depth 1 --single-branch --branch %s -- \"%s\" \"%s\"", lock_info.tag, url, install_folder)
		elseif lock_info.branch ~= nil then
			os.executef("git clone --depth 1 --single-branch --branch %s  -- \"%s\" \"%s\"", lock_info.branch, url, install_folder)
		elseif lock_info.rev ~= nil then
			-- it's a little difficult to fetch a singular revision from git, so instead we:

			-- intialize an empty repository
			os.executef("git -C \"%s\" init", install_folder)
			-- add the remote url as the origin
			os.executef("git -C \"%s\" remote add origin %s", install_folder, url)
			-- fetch the specific revision
			os.executef("git -C \"%s\" fetch --depth 1 origin %s", install_folder, lock_info.rev)
			-- reset the branch to the revision of interest
			os.executef("git -C \"%s\" reset --hard FETCH_HEAD", install_folder)
		else
			-- latest commit
			os.executef("git clone --depth 1 --single-branch -- \"%s\" \"%s\"", url, install_folder)
		end
	elseif lock_info ~= nil then
		-- we may need to update the branch, check with git-fetch
		local output, success = run_command(string.format("git -C \"%s\" fetch --dry-run", install_folder))
		if success then
			if string.len(output) > 0 then
				-- needs an update
				local format_str = "" 
				if lock_info.branch ~= nil then format_str = "Updating %s/%s/%s..." else format_str = "Updating %s/%s..." end
				log.info(string.format(format_str, lock_info.username, lock_info.repository, lock_info.branch))
				run_command(string.format("git -C \"%s\" reset --hard", install_folder))
				run_command(string.format("git -C \"%s\" pull", install_folder))
			end
		else
			error(string.format("Failed to validate the integrity of %s dependency: %s/%s", lock_info.type, lock_info.username, lock_info.repository))
		end
	end

	return lock_info.repository, install_folder
end

-- Github
pm.providers["gh"] = {
	lock = function(dep_str)
		-- generate the lock information
		local dep = github_like_lock(dep_str, "github", get_github_versions, get_github_tag)
		dep["type"] = "github"
		-- TODO: implement recursively reading manifest.json
		return {dep}
	end,

	-- downloads a depedency based on it's lock information 
	-- if its not already installs, also returns the folder that 
	-- the dependency was installed to
	install = function(lock_info)
		return github_like_install(lock_info, "gh", "https://github.com/%s/%s.git")
	end
}
pm.providers.gh.__index = pm.providers.gh

alias(pm.providers, "github", "gh")

-- Gitlab
pm.providers["gl"] = {
	lock = function(dep_str)
		local dep = github_like_lock(dep_str, "gitlab", get_gitlab_versions, get_gitlab_tag)
		dep["type"] = "gitlab"
		-- TODO: implement recursively reading manifest.json
		return {dep}
	end,

	-- downloads a depedency based on it's lock information 
	-- if its not already installs, also returns the folder that 
	-- the dependency was installed to
	install = function(lock_info)
		return github_like_install(lock_info, "gl", "https://gitlab.com/%s/%s.git")
	end
}
pm.providers.gl.__index = pm.providers.gl

alias(pm.providers, "gitlab", "gl")

-- regular path provider
pm.providers["path"] = {
	lock = function(dep_info)
		-- paths don't really have a specific version, so our job here is easy:
		-- store the path and optionally the name
		local lock_info = { type = "path" }
		if type(dep_info) == "string" then
			lock_info.path = dep_info
			-- the name should just be the last folder name in the chain
			lock_info.name = string.findlast(dep_info, "(%w+)")
		elseif type(dep_info) == "table" then
			lock_info.path = dep_info.path
			lock_info.name = dep_info.name or string.findlast(dep_info.path, "(%w+)")
		end

		local deps = nil
		if os.isfile(lock_info.path .. "/wares.json") then
			deps = pm.parse_manifest(lock_info.path .. "/wares.json")
		end

		return table.join({lock_info}, deps)
	end,

	install = function(lock_info)
		return lock_info.name, lock_info.path
	end
}

-- reads a manifest file and returns the lockfile information that should be generated from it
pm.parse_manifest = function(manifest_filename, settings)
	local manifest, err = json.decode(io.readfile(manifest_filename))
	if err == nil then
		-- we ignore the version key for now
		-- create the deps table
		local dependencies = {}
		for k, v in ipairs(manifest.dependencies) do
			-- depedencies can only either be a string or a table with more information
			--assert(type(v) == "string" or type(v) == "table", "depedencies array can only consist of strings or tables!")
			local lock_info = nil
			if type(v) == "string" then 
				-- the first order of business is determining the provider for the string
				local match_start, match_end, provider_id = string.find(v, "(%a+)")
				if provider_id ~= nil then
					local provider = pm.providers[provider_id]
					if provider ~= nil then
						lock_info = provider.lock(string.sub(v, match_end + 2))
					else
						error("Failed to find a provider for: " .. provider_id)
					end
				else
					error("Malformed dependency!")
				end
			elseif type(v) == "table" then
				if v.type ~= nil then
					local provider = pm.providers[v.type]
					if provider ~= nil then
						lock_info = provider.lock(v)
					else
						error("Failed to find a provider for: " .. v.type)
					end
				else
					error("Missing type field from dependency!")
				end
			else
				error("The dependencies array can only consist of strings or tables")
			end

			-- join the lock_info into the dependencies if it is unique
			-- table.insert(lockfile_data.dependencies, lock_info)
			for i, new_dep in ipairs(lock_info) do
				local unique = true
				local j = 1
				while unique and j <= #dependencies do
					unique = table.concat(new_dep) == table.concat(dependencies[j])
					j = j + 1
				end
				if unique then
					table.insert(dependencies, new_dep)
				end
			end
		end

		return dependencies
	else
		error(err)
	end
end

-- updates the lockfile
---@param non_default_dep_groups string[]
pm.update = function(non_default_dep_groups)
	-- create the lockfile table (always start in the root directory)
	local lockfile_data = { version = 0, dependencies = pm.parse_manifest(_MAIN_SCRIPT_DIR .. "/wares.json", non_default_dep_groups) }

	print(table.tostring(lockfile_data, 2))

	-- write lockfile
	local lockfile_str, err = json.encode(lockfile_data)
	if err == nil then
		io.writefile(get_lockfile_path(), lockfile_str)
	else
		error(err)
	end
end

-- installs required dependencies
---@return { [string]: string } # maps dependency names to their locations
pm.install = function()
	local lockfile_data, err = json.decode(io.readfile(get_lockfile_path()))
	if err == nil then
		-- ignore version key
		local dep_folders = {}
		-- for every dependency, lookup the installation provider
		for i, dependency in ipairs(lockfile_data.dependencies) do
			local provider = pm.providers[dependency.type]
			if provider ~= nil then
				-- return the installation directory for the dependency
				local dep_name, dep_folder = provider.install(dependency)
				dep_folders[dep_name] = dep_folder
			else
				error("Failed to find a provider for: " .. table.tostring(dependency, 1))
			end
		end
		return dep_folders
	else
		error(err)
	end
end

-- updates the lockfile and installs the required dependencies
-- sync only needs to be called by the top file, but should be called by 
-- any dependencies that want to change the settings
-- settings is a table of string boolean pairs representing whether to enable or disable certain dependency groups
-- returns a dictionary of the dependencies name and where it was installed
---@param settings {[string]: boolean}
---@return string[]
pm.sync = function(settings)
	local extra_deps_to_enable = {}
	if type(settings) == "table" then
		for k, v in pairs(settings) do
			if v == true then
				table.insert(extra_deps_to_enable, k)
			end
		end
	end
	
	-- TODO: only return the dependencies that are specified by the wares.json in this folder
	if pm.dep_folders and #extra_deps_to_enable == 0 then return pm.dep_folders end

	-- check to ensure a manifest file is present
	if not os.isfile("wares.json") then
		error("Failed to find a manifest file!")
	end

	local lockfile_path = get_lockfile_path()
	-- if the lock file doesn't exist or if extra deps need to be pulled, the lockfile needs updating
	local update_lockfile = #extra_deps_to_enable > 0 or not os.isfile(lockfile_path)

	if not update_lockfile then
		-- check if the lock file needs updating (the manifest file was updated more recently than the lock file)
		local manifest_stat = os.stat("wares.json")
		local lockfile_stat = os.stat(lockfile_path)

		update_lockfile = lockfile_stat.mtime < manifest_stat.mtime
	end

	if update_lockfile then
		if #extra_deps_to_enable > 0 then
			log.info("Update wares.lock... extra=" .. array.tostring(extra_deps_to_enable))
		else
			log.info("Updating wares.lock...")	
		end
		
		pm.update(extra_deps_to_enable)
	end

	log.info("Checking lockfile...")
	local dep_folders = pm.install()

	-- we should not have to sync again this run
	-- setting this variable before we look for other premake files ensure that no calls to pm.sync()
	-- do needless checks
	pm.dep_folders = dep_folders

	-- try to include any premake5.lua files
	for name, folder in pairs(dep_folders) do
		local status, result = pcall(include, folder)
		if not status then
			log.warn("Could not find a premake build file for " .. name .. ". You may have to manually create one.")
		end
	end

	return dep_folders
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

log.info("Wares v" .. tostring(pm.version) .. " (premake) loaded!")
return pm