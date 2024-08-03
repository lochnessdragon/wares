local utils = {}

-- returns a str where all the special characters (for lua matching) have been escaped
function utils.regex_escape(str)
	local lua_special = {"%", "(", ")", ".", "+", "-", "*", "?", "[", "^", "$"}
	for _, char in ipairs(lua_special) do
		pattern = "%" .. char
		str = string.gsub(str, pattern, "%" .. pattern)
	end

	return str
end

return utils