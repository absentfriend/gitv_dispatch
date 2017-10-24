--[[
---- Filename: live_dispatcher.lua
---- Description: 调度器主代码
---- 
---- Version:  2.0
---- Created:  2017年09月26日
---- Revision:  none
---- 
---- Author:  yangzhenzhen
---- Company: 银河互联网电视 2017 版权所有
--]]
--add SAXYD @20170117
--江苏联通增加按ip调度到不同机房，分别将苏州用户调度到苏州机房，其他走默认机房@20170122
--添加LNYD合作伙伴@20170122
-- 变量定义区
local uri                 = ngx.var.uri;
local request_uri         = ngx.var.request_uri;
local args                = ngx.req.get_uri_args();
--local time_now            = ngx.time(); -- 当前时间
local project_config      = nil;       -- 当前项目的配置信息
local project_id          = nil;       -- 当前项目ID
local cjson         = require("cjson");
-- 调度反馈结果
local dst_zone          = nil;   -- 目标地区
local dst_channel       = nil;   -- 目标频道
local dst_policy        = nil;   -- 目标策略
local dst_idc           = nil;   -- 目标IDC
local dst_idc_name      = nil;   -- 目标机房的名称
local dst_server        = nil;   -- 目标Server
local dispatcher_result = {};
local dst_cdn		= "gitv";
local live_service   ="live"
local history_service   ="tvod"
local shift_service   ="shift"
--调度IDC统计状态字典表
local m3u8_idc_stat_dict = ngx.shared.m3u8_idc_stat_dict;
--一个IDC的多块网卡调度状态字典
local policy_idc_server_stat_dict = ngx.shared.policy_idc_server_stat_dict;
---全局配置
local config = require "config"
local default_project = config.default_project
local dispatcher_version = config.dispatcher_version
--函数声明
local base = require("base")
local get_service_channel = base.get_service_channel
local get_service_type    = base.get_service_type
local find_policy         = base.find_policy
local get_default_policy  = base.get_default_policy
local compare_apkversion  = base.compare_apkversion
local dispatcher_idc      = base.dispatcher_idc
local send_dispatcher_result = base.send_dispatcher_result
local send_302_dispatcher_result = base.send_302_dispatcher_result
local project_exist       = base.project_exist
local dispatcher_server   = base.dispatcher_server
--第三方cdn处理函数
local cdn_processor = require "cdn_processor"
local process_third_cdn = cdn_processor.process_third_cdn
local get_zone_from_self_cdn = cdn_processor.get_zone_from_self_cdn
--
local utils         = require("utils_lua");

-------------------------------------- 主程序区 ------------------------------------
------------------------------------------------------------------------------------
-- 判断是否是V请求。此代码无用
--v_request = is_v_request(uri);
--ngx.log(ngx.INFO, "v_request = " .. tostring(v_request));

--判断项目是哪个合作伙伴
local project_area = args["area"];
-- 当前属于哪一个项目
local project_id = args["p"];
if project_id == nil then
	project_id = default_project;
end
-- 判断项目是否存在
local project_existed = project_exist(project_id);
if project_existed == false then
	ngx.log(ngx.ERR, "project: ", project_id, " is not existed.");
	return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
-- 获得当前项目的配置信息
local project_config = project_configs[project_id];
if project_config == nil then
	ngx.log(ngx.ERR, "can't get project: " .. project_id .. " config info.");
	return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
ngx.log(ngx.INFO, "project config: " .. cjson.encode(project_config));

-- 得到默认的区域
local default_zone = project_config["default_zone"];
local dst_channel = get_service_channel(uri);
if dst_channel == nil then
	ngx.log(ngx.ERR, "dst_channel is null, url=[" .. uri .. "]");
	return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
local service_type = get_service_type(uri, args);
if service_type == nil or service_type == "unknown" then
	ngx.log(ngx.ERR, "can't get service_type , url=[" .. request_uri .. "]");
	return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
ngx.log(ngx.INFO, "channel: " .. dst_channel .. ", service: " .. service_type);

--[[
  如果有合作伙伴是在第三方cdn上进行处理的，优先调度到第三方cdn上
  process_third_cdn 如果返回true认为可以在第三方处理，调度在此结束，如果返回false，往下处理走自己cdn
]]
local ret=false
local ret=process_third_cdn(project_area,service_type,dst_channel,args)
if ret then
    return ret
end

-----调度到自己cdn上
-- 设置调度服务，目前仅支持m3u8调度
local policy_service = "live" --- 此值为live或m3u8,对应live.xml m3u8.xml
if service_type ~= "live" then
        policy_service = "m3u8";
end
dst_zone=get_zone_from_self_cdn(args)
if dst_zone == nil then
    dst_zone = default_zone;
end
-- 根据区域得到调度策略
dst_policy = find_policy(policies, policy_service, dst_zone);
if dst_policy == nil then
	ngx.log(ngx.ERR, "can't find policy for " .. policy_service .. " and " .. dst_zone);
	return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
ngx.log(ngx.INFO, "get policy successfullly for " .. dst_zone);
-- 得到调度idc统计字典表
-- 根据请求的服务类型和得到的zone获取对应的服务器名称
dst_idc_name = dispatcher_idc(policy_service, dst_zone, dst_policy, m3u8_idc_stat_dict);
if dst_idc_name==nil then
    return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
--[[
-- 同一台机器的多块网卡随机调度????
dst_server = dispatcher_server(dst_idc_name);
if dst_server==nil or dst_server=="" then
	ngx.log(ngx.ERR, "dispatcher server failed for dst_idc_name: " .. dst_idc_name);
	return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end
]]
----同一台机器的多块网卡均衡调度？？？
--
dst_server=dispatcher_server_by_equalization(policy_service,dst_zone,dst_idc_name,policy_idc_server_stat_dict)

if dst_server == nil then
        ngx.log(ngx.ERR, "dispatcher server failed.");
        return ngx.exit(ngx.HTTP_NOT_ALLOWED);
end

-- 发送调度结果
local dst_uri = "http://" .. dst_server .. request_uri;
ngx.log(ngx.DEBUG,"dst_uri="..dst_uri);
if args["type"]==nil then
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_idc_name=dst_idc_name
    dispatcher_result.dst_uri=dst_uri
    if service_type == live_service or service_type==history_service or service_type == shift_service then
        dispatcher_result.dst_service=service_type
    end
    send_dispatcher_result(dispatcher_result)
elseif args["type"]=="2" then
    send_302_dispatcher_result(dst_uri);
end
