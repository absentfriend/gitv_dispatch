----配置变量
local config = require "config"
local cjson         = require("cjson");
--local m3u8_idc_stat_dict = ngx.shared.m3u8_idc_stat_dict;
--local policy_idc_server_stat_dict = ngx.shared.policy_idc_server_stat_dict;
local policy_idc_server_stat_dict_timeout = config.policy_idc_server_stat_dict_timeout
local dispatcher_version = config.dispatcher_version
local _M={}
_M._VERSION="2.0"

-- 函数定义区
-- 状态字典表key：zone + "-" + idc_name
-- policy      -> 某一种服务类型调度策略集合;
function _M.init_idc_stat(policy, dst_service,m3u8_idc_stat_dict,policy_idc_server_stat_dict) 
        --m3u8_idc_stat_dict:flush_all();
        --policy_idc_server_stat_dict:flush_all();

        -- k: zone name
        -- k1: idc name
        for k, v in pairs(policy) do
                for k1, v1 in pairs(v) do
                        -- 每一条策略，每一个IDC调度状态初始化
                        -- local key = k .. "-" .. k1;
                        local key = dst_service .. "-" .. k .. "-" .. k1; 
                        m3u8_idc_stat_dict:set(key, 0); 
                            
                        -- print("idc stat key: " .. key);
                        -- print("idc servers: " .. cjson.encode(idcs[k1]));

                        if idcs[k1] == nil then
                                print("can't find idc: ", k1, " for policy: ", k); 
                        else
                                for k2, v2 in pairs(idcs[k1]) do
                                        -- 每一条策略，每一个IDC下的每一台服务器的初始化
                                        -- key = k .. "-" .. k1 .. "-" .. v2["ip"];
                                        key = dst_service .. "-" .. k .. "-" .. k1 .. "-" .. v2["ip"];
                                        -- print("idc server stat key: " .. key);
                                        -- print(cjson.encode(v2));
                                        policy_idc_server_stat_dict:set(key, 0, policy_idc_server_stat_dict_timeout);
                                end 
                        end
                end
        end
end


function _M.file_existed(file_name)
        local file;
        local err;
        file, err = io.open(file_name);
        if file == nil then
                return false;
        else
                io.close(file);
                return true;
        end
end


function _M.get_table_len( t )
    local count = 0
    if type(t) ~= "table" then
        t={}
    end
    for k, v in pairs( t ) do
        count = count + 1
    end
    return count
end


function _M.is_v_request(uri)
    local i, j = string.find(uri, "/v.", 0, true);
    if i and j then
        return true;
    end

    return false;
end

function _M.get_service_channel(uri)
    local m,err = ngx.re.match(uri, "/[^?]+/(?<channel>[^?]+)/[^?]+","jox")
    if not m then
        return nil
    end
    if m["channel"] and m["channel"] ~= "" then
        return m["channel"]
    end
    return nil
end



function _M.get_service_type(uri, args)
        -- service_type: live, shift, history, jpg, images, unknown
        -- http://127.0.0.1/gitv_live/CCTV-1/CCTV-1.m3u8?p=GITV
        -- http://127.0.0.1/gitv_live/CCTV-1/CCTV-1.m3u8?p=GITV&t=-100
        -- http://127.0.0.1/gitv_live/CCTV-1/history.m3u8?p=GITV&start=100&end=200
        -- http://127.0.0.1/gitv_live/CCTV-1/live.jpg?p=GITV
        -- http://127.0.0.1/gitv_live/CCTV-1/images?p=GITV&t=100&direction=backward&step=10&num=10
    ngx.log(ngx.DEBUG,"request uri=%s",uri)
    local m = ngx.re.match(uri,"/[^?]+/(?<channel>[^?]+)/(?<filename>[^?]+)","jox")
    ngx.log(ngx.DEBUG,"m=%s",cjson.encode(m))
    local req_name=m["filename"]
    local channel = m["channel"]
    if not req_name or req_name == "" then
        ngx.log(ngx.DEBUG,"request file name unknown")
        return "unknown"
    end
    if not channel or channel =="" then
       ngx.log(ngx.DEBUG,"request channel unknown")
       return "unknown"
    end
    if req_name == "history.m3u8" and args['start'] ~=nil and args['end']~=nil then
        return "tvod"
    elseif req_name == "live.jpg" or req_name == "lm.jpg" then
        return "jpg"
    elseif req_name == "images" then
        return "images"
    elseif req_name  == channel..".m3u8" then
        local time_delta = args['t'];
        if time_delta ~= nil then
            num_seconds = tonumber(time_delta)
            if(num_seconds >= -10) then
                return "live"
            else
               return "shift"
            end
        else
               return "live"
        end
    end
    return "unknown";
end

function _M.find_policy(policies, service, zone)
        local policy = policies[service];
        
        if policy == nil then
                return nil;
        end
        print(cjson.encode(policy[zone]))
        return policy[zone];
end

function _M.get_default_policy(policies, service, default_)
        local policy = policies[service];

        if policy == nil then
                return nil;
        end

        return policy[default_policy_name];
end

local function lock_dispatcher_idc(policy, locked_idc)
        for k, v in pairs(policy) do
                if locked_idc == k then
                        return locked_idc, policy[k];
                end
        end

        ngx.log(ngx.ERR, "locked idc: ", locked_idc, " failed");
        return nil, nil;
end

---功能:找到调度次数最少的服务器，返回其服务器名
--参数：
--dst_service:live 或者 m3u8
--zone:例如:LANMU|CUCC_JIANGSU(dst_zone的值) 
--policy:{"JIANGSULIANTONG1":{"weight":50},"JIANGSULIANTONG2":{"weight":50},"JIANGSULIANTONG3":{"weight":50}}
--idc_stat_dict:记录每台服务器被调度的次数，如:live-LANMU|CUCC_JIANGSU-JIANGSULIANTONG1:某台服务器被调度到的次数
--返回值：调度次数最少的服务器名
--
--
function _M.dispatcher_idc(dst_service, zone, policy, m3u8_idc_stat_dict )
        local idc_stats = {};
        local minimum   = -1;
        local idc_name  = nil;
        local key_name  = nil;
        for k, v in pairs(policy) do
                local key = dst_service .. "-" .. zone .. "-" .. k;
                if v["weight"] > 0 then
                        idc_stats[key] = {};
                        idc_stats[key]["name"] = k;
                        idc_stats[key]["normalization"] = m3u8_idc_stat_dict:get(key)/v["weight"];
                end
        end
        ----policy==={"JIANGSULIANTONG1":{"weight":50}}
        ----m3u8_idc_stat_dict == live-LANMU|CUCC_JIANGSU-JIANGSULIANTONG1:调度的次数
        ----idc_stats === {"live-LANMU|CUCC_JIANGSU-JIANGSULIANTONG1":{"name":"JIANGSULIANTONG1","normalization":0}}
        --print(cjson.encode(idc_stats));

        for k, v in pairs(idc_stats) do
                if minimum == -1 then
                        minimum  = v["normalization"];
                        idc_name = v["name"];
                        key_name = k;
                end

                if v["normalization"] < minimum then
                        minimum  = v["normalization"];
                        idc_name = v["name"];
                        key_name = k;
                end
        end

        if key_name == nil then
                ngx.log(ngx.ERR, "can't find idc for cur policy: " .. cjson.encode(policy));
                return nil;
        end

        m3u8_idc_stat_dict:incr(key_name, 1);
        return idc_name;
end


----对同一台机器的对块网卡进行调度
function dispatcher_server_by_equalization(idc_service,zone_name, idc_name,policy_idc_server_stat_dict)
        local idc_servers = idcs[idc_name];
        if idc_servers == nil then
                ngx.log(ngx.ERR, "can't find idc server info for " .. idc_name);
                return nil;
        end

        local less_server = nil;
        local less_key    = nil;
        local less_count  = 0;

        for k, v in ipairs(idc_servers) do
                local key = idc_service.."-"..zone_name .. "-" .. idc_name .. "-" .. v["ip"];
                local count = policy_idc_server_stat_dict:get(key);
                if count == nil then
                        count = 0;
                        policy_idc_server_stat_dict:set(key, count, policy_idc_server_stat_dict_timeout);
                        ngx.log(ngx.INFO, "DICT TIME OUT, reset value.");
                end
                ngx.log(ngx.INFO, "key: " .. key .. "; count: " .. count);

                if less_server == nil then
                        less_server = v["ip"];
                        less_key    = key;
                        less_count  = count;
                        -- print("1- less_server: " .. less_server);
                else
                        -- print("2- less_server: " .. less_server .. "; less_count: " .. less_count .. "; count: " .. count);
                        if less_count > count then
                                less_server = v["ip"];
                                less_key    = key;
                                less_count  = count;
                        end
                end
        end
        if less_server == nil then
            ngx.log(ngx.ERR, "can't find idc ["..idc_name.."] in valid ip" );
            return nil;
        end
        -- 调整策略-机房-服务器调度次数值
        local key= idc_service.."-"..zone_name .. "-" .. idc_name .. "-" .. less_server;
        policy_idc_server_stat_dict:incr(key, 1);
        return less_server;
end

local function get_idc_status_data(idc_name)
        local redis = require "resty.redis";
        local red = redis:new();

        red:set_timeout(redis_timeout) -- 1 sec

        local ok, err = red:connect(redis_server, redis_port)
        if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return nil;
        end
        ngx.log(ngx.INFO, "connect redis successfully.");

        local res, err = red:get(idc_name);
        if not res then
                ngx.log(ngx.ERR, "failed to get dog: ", err);
                close_connection(red);
                return nil;
        end

        if res == ngx.null then
                close_connection(red);
                return "{}";
        end

        close_connection(red);
        return res;
end

local function is_excluded_server(server_ip, excluded_server_list)
        if excluded_server_list == nil then
                return false;
        end

        for k, v in ipairs(excluded_server_list) do
                if server_ip == v then
                        return true;
                end
        end

        return false;
end

local function get_dispatcher_server_list(idc_servers, excluded_server_list)
        local result_idc_servers = {};
        local count = 1;
        for k, v in ipairs(idc_servers) do
                local result = is_excluded_server(v["ip"], excluded_server_list);
                if result == false then
                        result_idc_servers[count] = v;
                        count = count + 1;
                end
        end

        return result_idc_servers;
end

--功能:将无效的ip排除掉之后随机返回一台服务器可用的ip，主要是针对一台机器多个ip的情况
--参数:idc名称和排除的机房列表
--返回值:返回一个可用的ip地址
--
function _M.dispatcher_server(idc_name)
        if idcs[idc_name] == nil then
                ngx.log(ngx.ERR, "can't find idc: ", idc_name);
                return nil;
        end
        ngx.log(ngx.DEBUG, "idc: ", idc_name, "; idc server list: ", cjson.encode(idcs[idc_name]));
        local excluded_server_list = get_excluded_server_list(excluded_servers);
        local idc_servers = get_dispatcher_server_list(idcs[idc_name],excluded_server_list);
        if  #idc_servers == 0 then
                ngx.log(ngx.ERR, "no idc server for dispatcher");
                return nil;
        end
        ngx.log(ngx.DEBUG, "idc servers: " .. cjson.encode(idc_servers));

        ---如果idc_servers中有多个ip，也即idc.xml中配置如下:
        -- <idc name="ANHUIYIDONG1">
        --    <h init="">10.25.130.156</h>
        --    <h init="">10.25.130.153</h>
        --    <h init="">10.25.130.152</h>
        --    <h init="">10.25.130.151</h>
        --</idc>
        --随机返回一个可用的ip
        --
        math.randomseed(ngx.now())
        local random_index=math.random(1,#idc_servers)
        local server_ip=idc_servers[random_index]["ip"]
        return server_ip;
end

function _M.send_302_dispatcher_result(dst_uri)
        --dst_uri = "http://" .. dst_server .. uri;
        return ngx.redirect(dst_uri, ngx.HTTP_MOVED_TEMPORARILY);
end

function _M.send_dispatcher_result(result)
    local dst_uri = result.dst_uri
    local dst_idc_name = result.dst_idc_name
    local dst_service     = result.dst_service
    local dst_cdn         = result.dst_cdn
    local stream_type     = result.stream_type
    local multicast_addr  = result.multicast_addr
    local dispatcher_result={}
    dispatcher_result["u"] = dst_uri;
    dispatcher_result["v"] = dispatcher_version;
    dispatcher_result["t"] = ngx.time();
    dispatcher_result["i"] = dst_idc_name;
    dispatcher_result["o"] = dst_service or "0";--live,tvod,shift
    dispatcher_result["c"] = dst_cdn;
    dispatcher_result["multicastAddr"]=multicast_addr
    dispatcher_result["streamType"] = stream_type
    local str_response = cjson.encode(dispatcher_result);
    ngx.header["Content-Length"] = tostring(#str_response);
    ngx.print(str_response);
end

function _M.send_error_result(msg)
        ngx.header["Content-Length"] = tostring(#msg);
    ngx.print(msg);
        return ngx.exit(ngx.HTTP_OK);
end

function _M.close_connection(red)
        local ok, err = red:set_keepalive(redis_max_idle_time, redis_pool_size);
        if not ok then
                ngx.log(ngx.ERR, "failed to set keepalive: ", err)
                return false;
        end
        return true;
end

function _M.project_exist(project_id)
        for k, v in pairs(project_configs) do
                if k == project_id then
                        return true;
                end
        end
        return false;
end

function _M.string_split(str, split_char)
        local sub_str_tab = {};
        while (true) do
                local pos = string.find(str, split_char)
                if (not pos) then
                        if str and #str > 0 then
                                sub_str_tab[#sub_str_tab + 1] = str
                        else
                                ngx.log(ngx.ERR, "string split: illegal string");
                        end
                        break;
                end

                local sub_str = string.sub(str, 1, pos - 1);
                if sub_str and #sub_str > 0 then
                        sub_str_tab[#sub_str_tab + 1] = sub_str;
                        str = string.sub(str, pos + 1, #str);
                else
                        str = string.sub(str, pos + 1, #str);
                end
        end
        return sub_str_tab;
end

function get_excluded_server_list(excluded_servers)
        if excluded_servers == nil or excluded_servers == "" then
                return nil;
        end
        return string_split(excluded_servers, "|");
end


--[[
function _M.compare_apkversion(v1,v2)
    local ver_list1={}
    local ver_list2={}
    for str in  string.gmatch(v1,"[^.]+") do ver_list1[#ver_list1+1]=str end
    for str in  string.gmatch(v2,"[^.]+") do ver_list2[#ver_list2+1]=str end
    local flag=0;
    for i=1 ,#(ver_list1) do
        if(tonumber(ver_list1[i])>tonumber(ver_list2[i])) then
            flag=1
            break
        elseif(tonumber(ver_list1[i])<tonumber(ver_list2[i])) then
            flag=-1
            break
        end
    end
    return flag
end
]]
--add:xds
local  function compare_online_time(starttime, endtime, onlinetime, deltatime_strat, deltatime_end)
    if endtime <= onlinetime then
        starttime = starttime + deltatime_strat
        endtime = endtime + deltatime_end

    elseif starttime > onlinetime then
        starttime = starttime
        endtime = endtime

    else
        starttime = starttime + deltatime_strat
        endtime = endtime
    end
    return starttime, endtime
end



return _M
