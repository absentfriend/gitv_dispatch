local m3u8_policy_file = "m3u8.xml"
local live_policy_file = "live.xml"
local cjson = require("cjson")
local function convert_2_idc(xml_idc) 
	local idc = {};
	local k, v;

	if xml_idc["weight"] == nil or xml_idc["weight"] == "" then
		idc["weight"] = 0;
	else
		idc["weight"] = tonumber(xml_idc["weight"]);
	end

	return idc;
end

local function convert_2_zone(xml_zone) 
	local zone = {};
	local k, v;
	for k, v in ipairs(xml_zone) do
		zone[v["name"]] = convert_2_idc(v);
	end

	return zone;
end
	
local function convert_2_policy(xml_policy)
	local policy = {};	
	local k, v;
	
	for k, v in ipairs(xml_policy) do
		policy[v["name"]] = convert_2_zone(v);
	end

	--print(cjson.encode(policy));
	return policy;
end

local function load_policy(policy_file)
	-- 加载策略文件。
	local xml_table = xml.load(policy_file);
		
	return convert_2_policy(xml_table);
end
local _M = {}
_M._VERSION = '2.0'

-- 公有函数
function _M.load_policies(policy_dir)
	local policies = {};
	policies["m3u8"] = load_policy(policy_dir .. m3u8_policy_file);
	policies["live"] = load_policy(policy_dir .. live_policy_file);
        return policies
end
return _M;
