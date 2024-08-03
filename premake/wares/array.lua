local array = {}

-- array pretty printer
---@param array any[]
---@return string
function array.tostring(array)
	local result = "["
	for i, item in ipairs(array) do
		if i > 1 then
			result = result .. ", "
		end
    result = result .. item
	end
	result = result .. "]"
	return result
end

return array