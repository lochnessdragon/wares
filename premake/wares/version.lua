-- Helper functions!
-- splits a string on a period
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

-- Version "class"
Version = { major = 0, minor = 0, patch = 0, pre_release = {}, build_meta = {}}

-- Version meta methods
Version.__index = Version
Version.__tostring =  function(self)
	local repr = string.format("%d.%d.%d", self.major, self.minor, self.patch)
	
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

Version.__eq = function(left, right)
  local equal = left.major == right.major and left.minor == right.minor and left.patch == right.patch
  equal = equal and #left.pre_release == #right.pre_release 
  if equal then 
    -- we now know that both tables have the same length, we can loop through them, checking for equality
    for i = 1, #left.pre_release do
      equal = equal and left.pre_release[i] == right.pre_release[i]  
    end
  end
  
  return equal
end

Version.__lt = function(left, right)
    local less_than = left.major < right.major
    if less_than then return less_than end -- early out
    if left.major > right.major then return false end -- left is actually greater than right
    
    less_than = left.minor < right.minor
    if less_than then return less_than end -- early out 
    if left.minor > right.minor then return false end -- left is actually greater than right
    
    less_than = left.patch < right.patch
    if less_than then return less_than end -- early out 
    if left.patch > right.patch then return false end -- left is actually greater than right
    
    -- check pre-release field(s)
    
    -- left has no pre-release fields?
    if #left.pre_release == 0 and #right.pre_release > 0 then return false end
    -- right has no pre-release fields?
    if #left.pre_release > 0 and #right.pre_release == 0 then return true end
    
    if #left.pre_release > 0 and #right.pre_release > 0 then 
      local field_count = math.min(#left.pre_release, #right.pre_release)  
      -- loop through all matching pre-release fields, testing for equality
      local pre_release_fields_equal = true
      for i = 1, field_count do 
        local left_is_number = tonumber(left.pre_release[i]) ~= nil
        local right_is_number = tonumber(right.pre_release[i]) ~= nil
        
        if left_is_number and right_is_number then 
          -- identifiers consisting of only digits are compared numerically.
          local left_number = tonumber(left.pre_release[i])
          local right_number = tonumber(right.pre_release[i])
          if left_number < right_number then 
            less_than = true
            pre_release_fields_equal = false
            break
          elseif right_number < left_number then
            less_than = false
            pre_release_fields_equal = false
            break
          end
        elseif not left_is_number and not right_is_number then 
          -- identifiers with letters or hyphens are compared lexically in ASCII sort order.
          -- lua compares strings in alphabetical order
          if left.pre_release[i] < right.pre_release[i] then 
            less_than = true
            pre_release_fields_equal = false
            break
          elseif right.pre_release[i] < left.pre_release[i] then 
            less_than = false
            pre_release_fields_equal = false
            break
          end
        elseif left_is_number and not right_is_number then 
          -- numeric identifiers always have lower precedence than non-numeric identifiers.
          less_than = true
          pre_release_fields_equal = false
          break
        elseif not left_is_number and right_is_number then
          -- numeric identifiers always have lower precedence than non-numeric identifiers.
          less_than = false
          pre_release_fields_equal = false
          break
        end
      end
      
      -- a larger set of pre-release fields has a higher precedence than a smaller set, if all of the preceding identifiers are equal.
      if pre_release_fields_equal then 
        if #left.pre_release > #right.pre_release then 
          less_than = false
        elseif #right.pre_release > #left.pre_release then 
          less_than = true
        end
      end
    end
    
    return less_than
end

Version.__le = function(left, right)
    return left == right or left < right
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
	
	local new_ver = { major = major, minor = minor, patch = patch, pre_release = pre_release, build_meta = build_meta }
	setmetatable(new_ver, self)

	return new_ver
end

function Version:from_str(semver_str)
	-- type checking
	assert(type(semver_str) == "string", "semver_str is not a string")
  
  -- we go a little off the rails from semver here, allowing things like:
  -- major-prerelease
  -- major.minor-prerelease
	local major = 0
	local minor = 0
	local patch = 0

	local next_start = 0
	
	for i in 1,3 do
		local match_start, match_end, field_str = string.find(semver_str, "(%d+)", next_start)
		if match_start == nil then error("Malformed semver: " .. semver_str) end
		if i == 1 then
			major = tonumber(field_str)
		elseif i == 2 then
			minor = tonumber(field_str)
		elseif i == 3 then
			patch = tonumber(field_str)
		end

		next_start = match_end

		-- can't find another field before the end? ==> break the loop
		local next_char = semver_str:sub(next_start + 1, next_start + 1)
		if not next_char == "." then break end
		next_start = next_start + 1
	end
	
	-- look for all of the pre-release field(s) following the major.minor.patch
	local pre_release_fields = {}
	match_start, match_end, _ = string.find(semver_str, "-", next_start)
	if match_start then
	  -- we now know that some pre-release info is attached
	  pre_release_fields, next_start = consume_dot_separated_fields(semver_str, match_end + 1)
	end
  
	-- look for all the build metadata field(s) following the -prerelease
	local build_metadata_fields = {}
	match_start, match_end, _ = string.find(semver_str, "%+", next_start)
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
	-- ^, ~, *, <, >, <=, >=, =, or a digit
	if string.startswith(comparison_semver, "^") then
		-- we've found a hat
		return VersionComparator:new({comparison_type = "^", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.startswith(comparison_semver, "~") then
		-- we've found a tilde
		return VersionComparator:new({comparison_type = "~", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.startswith(comparison_semver, "=") then
		-- we've found an equal sign
		return VersionComparator:new({comparison_type = "=", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.startswith(comparison_semver, ">=") then
		-- we've found an >= sign
		return VersionComparator:new({comparison_type = ">=", base_version = Version:from_str(string.sub(comparison_semver, 3))})
	elseif string.startswith(comparison_semver, "<=") then
		-- we've found an <= sign
		return VersionComparator:new({comparison_type = "<=", base_version = Version:from_str(string.sub(comparison_semver, 3))})
	elseif string.startswith(comparison_semver, ">") then
		-- we've found a > sign
		return VersionComparator:new({comparison_type = ">", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.startswith(comparison_semver, "<") then
		-- we've found a < sign
		return VersionComparator:new({comparison_type = "<", base_version = Version:from_str(string.sub(comparison_semver, 2))})
	elseif string.startswith(comparison_semver, "*") then
		-- we've found an asterisk in the major position
		return VersionComparator:new({comparison_type = "*_major", base_version = Version:new(0, 0, 0)})
	elseif not string.contains(comparison_semver, "*") then
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