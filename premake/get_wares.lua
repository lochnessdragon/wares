-- small script to download the wares package manager module and require it into a premake5
-- project script
error("Download this file directly from the releases on github!")

local version = {{WARES_VERSION}}
-- md5 hash of the wares file
local module_hash = {{WARES_HASH}}

-- check to see if wares has already been installed somewhere in the premake path
if pcall(require, "wares") then
	return require "wares"
end

-- download settings
local retry_count = 5

-- choose an install directory
local install_file = path.getabsolute("./wares/wares.lua")

-- generate the command needed for hashing
-- on windows, this is of the form:
-- certutil -hashfile "wares\wares.lua" MD5
-- on linux:
-- md5sum "wares\wares.lua"
-- on macos:
-- openssl md5 "wares\wares.lua"
os_id = os.host()
local hash_cmd = ""
if os_id == "windows" then
	hash_cmd = string.format("certutil -hashfile \"%s\" MD5", install_file)
elseif os_id == "linux" then
	hash_cmd = string.format("md5sum \"%s\"", install_file)
elseif os_id == "macosx" then
	hash_cmd = string.format("cat \"%s\" | md5", install_file)
end

function progress(total, current)
  local ratio = current / total;
  ratio = math.min(math.max(ratio, 0), 1);
  local percent = math.floor(ratio * 100);
  print("Wares download progress (" .. percent .. "%/100%)")
end

for i = 1, retry_count do
	local result_str, response_code = http.download(string.format("https://github.com/lochnessdragon/wares/releases/download/v%s/wares.lua", version), install_file, { progress = progress })

	if result_str ~= "OK" then
		term.pushColor(term.errorColor)
		print("[error]: failed to download wares.lua: " .. result_str)
		if i <= retry_count then print("retrying... (" .. i .. ")") end
		term.popColor()
		goto continue
	end

	-- check has
	-- Failure states:
	-- failed to run the command, this is a warning
	-- we don't know the command for this operating system, this is a warning
	-- the hashes do not match. this is an actual error, report it and retry download

	if hash_cmd == "" then
		-- unknown command, warn about the integrity of the file
		term.pushColor(term.warningColor)
		print("[warn]: failed to validate the integrity of wares.lua (unknown os)")
		term.popColor()
		goto escape
	end

	local console_handle = io.popen(hash_cmd)
	local hash_output = console_handle:read("*a")
	local result = console_handle:close()

	if result == 0 then
		-- hash function succeeded
		local hash = ""
		if os_id == "windows" then
			-- extract hash
			-- looks something like:
			-- MD5 hash of <path>:
			-- 2e9d229043106b624b9da4c63be01207
			-- CertUtil: -hashfile command completed successfully.
			local match_start, match_end, potential_hash = string.find(hash_output, "MD5 hash of " .. install_file .. ":\n(%w+)")
			if potential_hash ~= nil then 
				hash = potential_hash
			else
				term.pushColor(term.errorColor)
				print("[error]: failed to extract hash string.")
				if i <= retry_count then print("retrying... (" .. i .. ")") end
				term.popColor()
				goto continue
			end
		elseif os_id == "linux" then
			-- extract hash
			-- looks something like:
			-- 2e9d229043106b624b9da4c63be01207  <path>
			local match_start, match_end, potential_hash = string.find(hash_output, "(%w+)")
			if potential_hash ~= nil then 
				hash = potential_hash
			else
				term.pushColor(term.errorColor)
				print("[error]: failed to extract hash string.")
				if i <= retry_count then print("retrying... (" .. i .. ")") end
				term.popColor()
				goto continue
			end
		elseif os_id == "macosx" then
			-- extract hash
			-- looks something like:
			-- 2e9d229043106b624b9da4c63be01207
			local match_start, match_end, potential_hash = string.find(hash_output, "(%w+)")
			if potential_hash ~= nil then 
				hash = potential_hash
			else
				term.pushColor(term.errorColor)
				print("[error]: failed to extract hash string.")
				if i <= retry_count then print("retrying... (" .. i .. ")") end
				term.popColor()
				goto continue
			end
		end

		if module_hash ~= hash then
			term.pushColor(term.errorColor)
			print("[error]: failed to validate wares.lua")
			if i <= retry_count then print("retrying... (" .. i .. ")") end
			term.popColor()
			goto continue
		end
	else
		-- hash function failed, warn about the integrity of the file
		term.pushColor(term.warningColor)
		print("[warn]: failed to validate the integrity of wares.lua (script error)")
		term.popColor()
	end

	::escape::
	return require "wares"

	::continue::
end