--[[
---- Filename: init.lua
---- Description: 调度器初始化
---- 
---- Version:  1.0
---- Created:  2012年09月29日 11时23分51秒
---- Revision:  none
---- 
---- Author:  聂汉子 (niehanzi), kedahanzi@163.com
---- Company: 家视天下 2013 版权所有
--]]

require("LuaXml") 
local cjson         = require("cjson");
local idc_parser    = require("idc_parser");
local utils         = require("utils_lua");
-- 加载配置文件
local config=require "config"
local conhash_replica_count = config.conhash_replica_count;
local policy_idc_server_stat_dict_timeout = config.policy_idc_server_stat_dict_timeout

---加载函数
local base = require "base"
local file_existed = base.file_existed
local init_idc_stat = base.init_idc_stat
local get_table_len = base.get_table_len
local policy_parser = require("policy_parser");
local load_policies = policy_parser.load_policies
-- 初始化字典表
local m3u8_idc_stat_dict = ngx.shared.m3u8_idc_stat_dict;
local policy_idc_server_stat_dict = ngx.shared.policy_idc_server_stat_dict;
m3u8_idc_stat_dict:flush_all();
policy_idc_server_stat_dict:flush_all();
local data_dir=config.data_dir;
local idc_data_file=config.idc_data_file;


-- 全局变量定义
policies         = nil; -- 全局调度策略
project_configs = {};  --项目配置表
project_ip_zones = {};  -- 全局IP库
idcs             = nil; -- 所有IDC机房的数据
server_idc_map   = nil; -- 每一个IP所属IDC的映射表
--idc_conhashs     = nil; -- 每一个IDC由其服务列表构造的一致性哈希实例

-- 为了支持多项目，各个项目IP库分开,防止干扰

project_configs["GITV"]   = {   name="LanMuDianBo",
                                        ip_lib="ip_lib_lanmudianbo.data",
                                        default_zone="LANMU|DEFAULT",
                                        default_policy="LANMU|DEFAULT"};
project_configs["SHOW"] = {     name="SHOW",
                                        ip_lib="ip_lib_show.data",
                                        default_zone="CMCC|JIANGSU",
                                        default_policy="CMCC|JIANGSU"};
project_configs["XINJIANG"] = { name="XinJiang",
                                        ip_lib="ip_lib_xinjiang.data",
                                        default_zone="CMCC|XINJIANG",
                                        default_policy="CMCC|XINJIANG"};

project_configs["NEIMENG"] = {  name="NeiMeng",
                                        ip_lib="ip_lib_neimeng.data",
                                        default_zone="RADIO|NEIMENG",
                                        default_policy="RADIO|NEIMNEG"};

-- 遍历所有项目的调度器，加载IP库
for k, v in pairs(project_configs) do
	local ip_lib_file= data_dir .. project_configs[k]["ip_lib"];

	if file_existed(ip_lib_file) == true then
		project_ip_zones[k] = utils.ip_zones_load(ip_lib_file);
		if not project_ip_zones[k] then
			ngx.log(ngx.ERR, "loading ip zones failed.");
		else
			ngx.log(ngx.INFO, "loading ip zones is over");
		end
	else
		ngx.log(ngx.ERR, "can't find file: ", ip_lib_file);	
	end
end



-- 加载idc机房数据
idcs  = idc_parser.load_idcs(data_dir .. idc_data_file);
if not idcs or get_table_len(idcs) <= 0 then
	ngx.log(ngx.ERR, "loading idc data failed");
else
	ngx.log(ngx.INFO, "loading idc data is over");
end
-- print("-------------------------" .. cjson.encode(idcs));


policies=policy_parser.load_policies(data_dir);
-- 初始化机房调度状态
local m3u8_policy = policies["m3u8"];
init_idc_stat(m3u8_policy, "m3u8",m3u8_idc_stat_dict,policy_idc_server_stat_dict);
local live_policy = policies["live"];
init_idc_stat(live_policy, "live",m3u8_idc_stat_dict,policy_idc_server_stat_dict);

