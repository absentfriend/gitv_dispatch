local cjson = require "cjson"
--local server_idc_map = {};--无用

-- 私有函数
local function convert_2_server(xml_server, idc_name)
    local server = {};
    server["init"] = xml_server["init"];
	if xml_server["enable"] == "0" then
		return nil;	
	end

    	server["ip"] = xml_server[1];
	--server_idc_map[xml_server[1]] = idc_name;
	--ngx.log(ngx.ERR, "server: ", cjson.encode(server));
	--ngx.log(ngx.ERR, "server idc map: ", cjson.encode(server_idc_map));
    return server;
end

local function convert_2_idc(xml_idc) 
	local idc = {};
	local k, v;

	for k, v in ipairs(xml_idc) do
		local server = convert_2_server(v, xml_idc["name"]);
		if server ~= nil then
			idc[k] = server;
		end
	end

	return idc;
end

local function convert_2_idcs(xml_idcs) 
	local idcs = {};
	local k, v;
	
	for k, v in ipairs(xml_idcs) do
		idcs[v["name"]] = convert_2_idc(v);
	end
	return idcs;
end
local _M = {}   
_M._VERSION = '2.0'
-- 公有函数
function _M.load_idcs(idc_data_file)
	-- 加载idc数据文件
	local xml_table = xml.load(idc_data_file);
	return convert_2_idcs(xml_table);
end

return _M;
