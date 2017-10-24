--[[
---- Filename: config.lua
---- Description: 配置文件
---- 
---- Version:  1.0
---- Created:  2012年09月29日 11时23分51秒
---- Revision:  none
---- 
---- Author:  聂汉子 (niehanzi), kedahanzi@163.com
---- Company: 银河互联网电视 2014 版权所有
--]]

-- 数组文件目录

local _M = {}   
_M._VERSION = '2.0'

_M.data_dir          = "/opt/soft/nginx/data/";


_M.server_list = {};

-- IDC机房数据文件 
_M.idc_data_file       = "idc.xml";

-- 系统版本
_M.dispatcher_version  = "2017-09-26 v2.0.0";

-- 默认项目
_M.default_project     = "SHOW";

-- 一致性哈希节点复制的份数
_M.conhash_replica_count = 500;

-- 字典表超时时间, 3600秒，一个小时
_M.policy_idc_server_stat_dict_timeout = 3600;


return _M;
