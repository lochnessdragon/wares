-- small script to download the wares package manager module and require it into a premake5
-- project script
error("Download this file directly from the releases on github!")

local version = {{WARES_VERSION}}
local module_hash = {{WARES_HASH}}

function progress(total, current)
  local ratio = current / total;
  ratio = math.min(math.max(ratio, 0), 1);
  local percent = math.floor(ratio * 100);
  print("Wares download progress (" .. percent .. "%/100%)")
end

http.download(string.format("https://github.com/lochnessdragon/wares/releases/download/v%s/wares.lua", version), "wares/wares.lua", { progress = progress })

return require "wares"