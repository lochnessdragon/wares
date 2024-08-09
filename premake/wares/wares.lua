require ("wares_native")

local wares = {}

local log = {}

log.info = function(msg)
	term.pushColor(term.lightGreen)
	print("[wares]: " .. msg)
	term.popColor()
end

log.warn = function(msg)
	term.pushColor(term.warningColor)
	print("[wares/warn]: " .. msg)
	term.popColor()
end

log.error = function(msg)
	term.pushColor(term.errorColor)
	print("[wares/error]: " .. msg)
	term.popColor()
end

wares.sync = function(extra_deps, dont_include) 
	if extra_deps == nil then
		extra_deps = {}
	end

	-- if extra_deps is "dep name"=bool, convert it to 
	-- ["dep name", ...] array
	local actual_extra_deps = {}
	for dep_name, should_include in pairs(extra_deps) do
		if type(should_include) == "boolean" then
			if should_include then
				table.insert(actual_extra_deps, dep_name)
			end
		elseif type(should_include) == "string" then
			table.insert(should_include)
		end
	end

	if dont_include == nil then
		dont_include = {}
	end

	local overrides = {}
	for option_name, folder in pairs(_OPTIONS) do
		if string.startswith(option_name, "override:") and folder ~= nil then
			overrides[string.sub(option_name, 10)] = folder
		end
	end

	local result = wares_native.sync_backend(_MAIN_SCRIPT_DIR, os.realpath("./"), _OPTIONS["wares-cache"], actual_extra_deps, overrides)

	if type(result) == "string" then 
		error("wares backend error: " .. result)
	end

	-- print(table.tostring(result, 1))

	for dep_name, folder in pairs(result) do
		-- create new options from the result for overrides to prevent premake from erroring out on an unknown option
		newoption {
			trigger     = "override:" .. dep_name,
			value       = "PATH",
			description = "Override the directory that " .. dep_name .. "is installed to. This will not do any version checking.",
			category    = "Wares Options",
		}

		-- auto include dependnecies that are not in the dont_include array (if they have a premake5.lua file)
		if not table.contains(dont_include, dep_name) then
			if os.isfile(folder .. "/premake5.lua") then
				local status, result = pcall(include, folder)
				if not status then
					log.warn("Failed to include build file for " .. dep_name .. ".")
				end
			end
		end
	end

	return result
end

-- option: wares_cache the folder that sources should be downloaded to
newoption {
	trigger 	= "wares-cache",
	value 		= "path",
	description = "Choose where wares' cache should be stored.",
	category 	= "Wares Options"
}

return wares