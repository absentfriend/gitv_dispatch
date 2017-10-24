
local live_service   = "live"
local history_service   ="tvod"
local shift_service   = "shift"

local base = require "base"
local send_dispatcher_result = base.send_dispatcher_result
--local compare_apkversion     = base.compare_apkversion

local utils         = require("utils_lua");
local cjson         = require("cjson")
---频道配置
local channel =  require "channel"
local liaoning_huawei_channel_list    = channel.liaoning_huawei_channel_list
local saxiyd_huawei_channel_list      = channel.saxiyd_huawei_channel_list
local ynyd_zhongxing_channel_list     = channel.ynyd_zhongxing_channel_list
local ynyd_huawei_channel_list        = channel.ynyd_huawei_channel_list
local anhui_cmcc_upgrade_channel_list = channel.anhui_cmcc_upgrade_channel_list
local shjidi_upgrade_channel_list     = channel.shjidi_upgrade_channel_list
local zhejiang_upgrage_channel_list   = channel.zhejiang_upgrage_channel_list
local jiangsu_cmcc_huawei_upgrage_channel_list = channel.jiangsu_cmcc_huawei_upgrage_channel_list
local hbjd_channel_list_zhongxing     = channel.hbjd_channel_list_zhongxing
local jiangsu_zhongxing_upgrage_channel_list = channel.jiangsu_zhongxing_upgrage_channel_list
local ynyd_multicast_channel_list    = channel.ynyd_multicast_channel_list

---const
local unicast = "unicast"
local multicast ="multicast"

local function compare_apkversion(v1,v2) 
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



local function liaoning_huawei_processor(dst_service,channel_list,dst_channel,args)
    local icpid="88888891";
    local dst_uri = channel_list[dst_channel];
    local dst_cdn = "LNYD";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri=""
    if dst_service == live_service and dst_uri ~= nil  then
        local service_type="1";
	dst_request_uri = string.format("%s?servicetype=%s&icpid=%s", dst_uri,service_type,icpid);
	ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif dst_service == history_service and dst_uri ~= nil  then
	local time_start    = tonumber(args['start'], 10) or ngx.time();
	local time_end      = tonumber(args['end'], 10) or ngx.time();
	local start_time = os.date("%Y%m%d%H%M%S", time_start)
	local end_time = os.date("%Y%m%d%H%M%S", time_end)
	dst_request_uri = string.gsub(dst_uri,"PLTV","TVOD")
	local service_type="3";
	dst_request_uri = string.format("%s?PlaySeek=%s-%s&servicetype=%s&icpid=%s",dst_request_uri,start_time,end_time,service_type,icpid);
	ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    end
    if dst_request_uri ~="" and dst_request_uri~=nil then
        dispatcher_result.dst_uri=dst_request_uri
	send_dispatcher_result(dispatcher_result);
	return true;
    end
    return false
end

---陕西移动华为
local function saxiyd_huawei_processor(dst_service,channel_list,dst_channel,args)
    local dst_cdn = "huawei"
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_uri = channel_list[dst_channel];
    if (dst_service == live_service or dst_service == history_service) and dst_uri ~= nil  and compare_apkversion(args['apkVersion'],'2.3.15')>=0  then
        dispatcher_result.dst_uri=dst_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false;
end

local function get_client_network_type()
        local client_ip = ngx.var.remote_addr
        local start_i, end_i = string.find(client_ip, "^10.")
        if start_i~=nil and end_i~=nil then
                return multicast
        end
        return unicast
end

---云南移动华为
local function ynyd_huawei_processor(dst_service,channel_list,dst_channel,args)
    local dst_uri = channel_list[dst_channel];
    if dst_uri == nil then
        return false
    end
    local dst_cdn = "ynydhw";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local icpid="88888894"
    if  compare_apkversion(args['apkVersion'],'2.3.17')>=0 and (dst_service==live_service or dst_service==history_service or dst_service==shift_service)   then 
        ngx.log(ngx.INFO, "dst_uri: " .. dst_uri);
        dispatcher_result.dst_uri=dst_uri
        dispatcher_result.stream_type=unicast
        if dst_service==live_service then
            local client_type = get_client_network_type()
            if client_type == multicast then
                local multicast_addr=ynyd_multicast_channel_list[dst_channel]
                if multicast_addr ~=nil then
                    dispatcher_result.multicast_addr=multicast_addr
                    dispatcher_result.stream_type=multicast
                    send_dispatcher_result(dispatcher_result);
                    return true
                end
            end
        end 

        send_dispatcher_result(dispatcher_result);
    	return true;
    else
        local dst_request_uri="";
        if dst_service == live_service then
           --http://122.229.7.72/PLTV/88888888/224/3221226957/index.m3u8?icpid=88888888&servicetype=1 
            local service_type="1";
            dst_request_uri = string.format("%s?servicetype=%s&icpid=%s", dst_uri,service_type,icpid);
            ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
        --[[
        elseif dst_service == shift_service then
            --http://122.229.7.72/PLTV/88888888/224/3221226957/index.m3u8?icpid=88888888&servicetype=2&npt=-X
            local shift_time=args['t']-30
            local service_type="2"
            dst_request_uri = string.format("%s?servicetype=%s&npt=%s&icpid=%s", dst_uri,service_type,shift_time,icpid);
            ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
        ]]
        elseif dst_service == history_service then
            --http://122.229.7.72/TVOD/88888888/224/3221226957/index.m3u8?icpid=88888888&servicetype=3&playseek=20151028193500-20151028200500
            local time_start    = tonumber(args['start'], 10);
            local time_end      = tonumber(args['end'], 10);
            local start_time = os.date("%Y%m%d%H%M%S", time_start)
            local end_time = os.date("%Y%m%d%H%M%S", time_end)
            local dst_uri = string.gsub(dst_uri,"PLTV","TVOD")
            local service_type="3";
            dst_request_uri = string.format("%s?PlaySeek=%s-%s&servicetype=%s&icpid=%s",dst_uri,start_time,end_time,service_type,icpid);
            ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
        end
        if dst_request_uri ~=nil and  dst_request_uri~="" then
            dispatcher_result.dst_uri=dst_request_uri     
            send_dispatcher_result(dispatcher_result);
            return true;
        end
    end
    return false;
end



local function ynyd_zhongxing_processor(dst_service,channel_list,dst_channel,args)
--[[
直播测试：
http://39.130.192.215:6060/gitv_live/G_QINGHAI/G_QINGHAI.m3u8?AuthInfo=xxx&version=xxx&sss=xxx
时移测试：
http://39.130.192.215:6060/000000002000/G_QINGHAI/index.m3u8?AuthInfo=xxx&version=xxx&sss=xxx&starttime=20160927T095000.00Z
回看测试：
http://39.130.192.215:6060/000000002000/G_QINGHAI/index.m3u8?AuthInfo=xxx&version=xxx&sss=xxx&starttime=20160927T095000.00Z&endtime=20160927T100000.00Z
]]
    local dst_uri = channel_list[dst_channel];
    if dst_uri == nil then
        return false
    end
    local dst_cdn = "ynydzx";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = ""
    if  dst_service == live_service  then
        dst_request_uri = dst_uri
        dispatcher_result.dst_uri=dst_uri
        dispatcher_result.stream_type=unicast
        local client_type = get_client_network_type()
        if client_type == multicast then
            local multicast_addr=ynyd_multicast_channel_list[dst_channel]
            if multicast_addr ~=nil then
                dispatcher_result.multicast_addr=multicast_addr
                dispatcher_result.stream_type=multicast
                send_dispatcher_result(dispatcher_result);
                return true
            end
        end
    elseif  dst_service == shift_service  then
        local start_timestamp=ngx.now()+tonumber(args['t'])-120;
        --UTC时间
        local start_time = os.date("!%Y%m%dT%H%M%S.00Z",start_timestamp)
        --local livemode="2";
        local func = function (m)
            return m[1].."/".."000000002000".."/"..m[3].."/index.m3u8"..m[5]
        end
        dst_request_uri, n, err = ngx.re.gsub(dst_uri, "(.+)/(.+)/(.+)/(.+).m3u8(.*)", func, "jo")
        if  err == nil  then
            dst_request_uri = string.format("%s&starttime=%s",dst_request_uri,start_time);
            ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
        else
            ngx.log(ngx.ERR,"gsub error=%s",err)
            return false;
        end
    elseif  dst_service == history_service then
        local format_str="%s%s%sT%s%s%s.00Z"
        local start_timestamp    = tonumber(args['start'], 10);
        local end_timestamp    = tonumber(args['end'], 10);
        --local livemode="4";
        local start_time = os.date("!%Y%m%dT%H%M%S.00Z",start_timestamp)
        local end_time = os.date("!%Y%m%dT%H%M%S.00Z",end_timestamp)
        local func = function (m)
            return m[1].."/".."000000002000".."/"..m[3].."/index.m3u8"..m[5]
        end
        dst_request_uri, n, err = ngx.re.gsub(dst_uri, "(.+)/(.+)/(.+)/(.+).m3u8(.*)", func, "jo")
        if  err == nil  then
            dst_request_uri = string.format("%s&starttime=%s&endtime=%s",dst_request_uri,start_time,end_time);
            ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);

        else
            ngx.log(ngx.ERR,"gsub error=%s",err)
            return false
        end
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false
end


local function zhejiang_yidong_huawei_processor(dst_service,channel_list,dst_channel,args)
--http:\/\/cdnrr.zj.chinamobile.com\/110000001001\/AHWS\/filename.m3u8?p=GITV&livemode=1
--http:\/\/cdnrr.zj.chinamobile.com\/110000002001\/AHWS\/filename.m3u8?starttime=20171001T115508.00Z&endtime=20171001T115738.00Z&p=GITV&livemode=4
    local dst_uri = channel_list[dst_channel]
    if dst_uri == nil then
        return false
    end
    local dst_cdn = "huawei";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = ""
    local host_ip= "cdnrr.zj.chinamobile.com"
    if  dst_service == live_service   then
        dst_request_uri = dst_uri;
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif  dst_service == history_service then
        local dst_uri = "http://%s/%s/%s/filename.m3u8?starttime=%sT%sZ&endtime=%sT%sZ&p=GITV&livemode=%s";
        local dst_request_uri = "";
        local start_delay_time = 240
        local end_delay_time = 360
        local time_start    = tonumber(args['start'], 10)+start_delay_time;
        local time_end      = tonumber(args['end'], 10)+end_delay_time;
        local start_date = os.date("%Y%m%d", time_start);
        local start_time = os.date("%H%M%S.00", time_start);
        local end_date = os.date("%Y%m%d", time_end);
        local end_time = os.date("%H%M%S.00", time_end);
        local code = "110000002001";
        local mode = "4";
        dst_request_uri = string.format(dst_uri,host_ip, code, dst_channel, start_date, start_time, end_date, end_time, mode);
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false;
end

local function guangdong_jidi_processor(dst_service,channel_list,dst_channel,args)
    local dst_uri = channel_list[dst_channel]
    if dst_uri == nil then
        return false
    end
    local dst_cdn = "sihua";

    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = ""
    --http://gslbserv.itv.cmvideo.cn/x.m3u8?channel-id=ygyhlive&Contentid=9000078517&livemode=4&starttime=20151029T143000.00Z&endtime=20151029T143800.00Z
    if  dst_service == history_service  then
        local time_start    = tonumber(args['start'], 10);
        local time_end      = tonumber(args['end'], 10);
        local start_date = os.date("%Y%m%d", time_start);
        local start_time = os.date("%H%M%S.00", time_start);
        local end_date = os.date("%Y%m%d", time_end);
        local end_time = os.date("%H%M%S.00", time_end);
        local dst_request_uri = "";
        dst_request_uri = string.format("%s&livemode=%s&starttime=%sT%sZ&endtime=%sT%sZ",dst_uri,"4",start_date,start_time,end_date,end_time);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif  dst_service == live_service  then
        dst_request_uri = string.format("%s&livemode=%s", dst_uri,"1");
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false;
end

local function jiangsu_cmcc_huawei_processor(dst_service,channel_list,dst_channel,args)
    local dst_uri = channel_list[dst_channel];
    print("dst_service="..dst_service.." dst_channel="..dst_channel..",area="..args["area"]);
    local dst_cdn = "huawei";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = ""

    if  dst_service == live_service and dst_uri ~= nil then
        dst_request_uri = dst_uri
    elseif dst_service == shift_service and dst_uri ~= nil and  compare_apkversion(args['apkVersion'],'2.5.01')>=0  then
        local starttime=tonumber(args['t'])-20
        dst_request_uri = string.gsub(dst_uri,"live1","tstv");
        dst_request_uri = string.format("%s?npt=%s", dst_request_uri,starttime);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif  dst_service == history_service and dst_uri ~= nil then
        local start_delay_time = 60
        local end_delay_time =  90  
        local time_start = 0;  
        local time_end = 0;
        time_start = tonumber(args['start'], 10) - start_delay_time;
        time_end = tonumber(args['end'], 10) + end_delay_time;
        local start_time = os.date("%Y%m%d%H%M%S", time_start)
        local end_time = os.date("%Y%m%d%H%M%S", time_end)
        dst_request_uri = string.gsub(dst_uri,"live1","lookback");
        dst_request_uri = string.format("%s?PlaySeek=%s-%s", dst_request_uri, start_time, end_time);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        if compare_apkversion(args['apkVersion'],'2.6.21')>0 then
            dst_request_uri=string.gsub(dst_request_uri,"(.+)/gitv/(.*)","%%s/gitv/%2")
        end
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false;

end

local function  jiangsu_cmcc_zhongxing_processor(dst_service,channel_list,dst_channel,args)
    local dst_uri = channel_list[dst_channel];
    if dst_uri == nil then
        return false
    end
    local dst_cdn = "zhongxing";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = ""

    if dst_service == "live" then
        dst_request_uri=dst_uri
    elseif dst_service == "shift" then
        local starttime=tonumber(args['t'])-20
        dst_uri= string.gsub(dst_uri,"live1","tstv");
        dst_request_uri = string.format("%s?npt=%s", dst_uri,starttime);
    elseif dst_service == "history" then
        local start_delay_time = 60
        local end_delay_time =  90
        local time_start = 0;
        local time_end = 0;
        time_start = tonumber(args['start'], 10) - start_delay_time;
        time_end = tonumber(args['end'], 10) + end_delay_time;
        local start_time = os.date("%Y%m%d%H%M%S", time_start)
        local end_time = os.date("%Y%m%d%H%M%S", time_end)
        local dst_request_uri = "";
        dst_uri = string.gsub(dst_uri,"live1","lookback");
        dst_request_uri = string.format("%s?PlaySeek=%s-%s", dst_uri, start_time, end_time);
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false;
end


local function hebei_jidi_processor(dst_service,channel_list,dst_channel,args)
    local dst_uri = channel_list[dst_channel];
    local dst_cdn = "zhongxing";
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = ""
    --if (dst_service==live_service or dst_service==shift_service) and dst_uri~=nil then
    if dst_service==live_service  and dst_uri~=nil then
        local livemode="1";
        dst_request_uri = string.format("%s?livemode=%s",dst_uri,livemode);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif dst_service==history_service and dst_uri~=nil then
        dst_request_uri = string.gsub(dst_uri,"030000001000","030000002000");
        local start_delay_time = 200
        local end_delay_time =  450 ---河北有反馈回看前边播太多，后边不完整，后边多加2分钟@20171017
        local time_start    = tonumber(args['start'], 10)+start_delay_time;
        local time_end      = tonumber(args['end'], 10)+end_delay_time;
        local start_date = os.date("%Y%m%d", time_start);
        local start_time = os.date("%H%M%S.00", time_start);
        local end_date = os.date("%Y%m%d", time_end);
        local end_time = os.date("%H%M%S.00", time_end);
        local livemode="4";
        dst_request_uri = string.format("%s?starttime=%sT%sZ&endtime=%sT%sZ&livemode=%s",dst_request_uri,start_date,start_time,end_date,end_time,livemode);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false;
end


local function anhui_cmcc_processor(dst_service,channel_list,dst_channel,args)
    local dst_uri = channel_list[dst_channel]
    local dst_cdn = "fenghuo";
    if dst_uri== nil or compare_apkversion(args['apkVersion'],'2.3.9') < 0 then
        return false
    end
    local dispatcher_result={}
    dispatcher_result.dst_cdn = dst_cdn
    dispatcher_result.dst_service=dst_service
    local dst_request_uri = "" 
    if dst_service == live_service   then
        dst_request_uri = dst_uri;
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif dst_service == shift_service  then
        local starttime=ngx.time()+tonumber(args['t'])-30
        dst_request_uri = string.gsub(dst_uri,"120000001002","120000003002");
        local livemode="2"
        dst_request_uri = string.format("%s?starttime=%s&livemode=%s", dst_request_uri,starttime,livemode);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    elseif dst_service == history_service and ngx.now()- tonumber(args['start'])<= 604800  then
        dst_request_uri = string.gsub(dst_uri,"120000001002","120000002002");
        local livemode="4"
        local start_delay_time = -60
        local end_delay_time = 120
        local time_start    = tonumber(args['start'], 10)+start_delay_time;
        local time_end      = tonumber(args['end'], 10)+end_delay_time;
        dst_request_uri = string.format("%s?starttime=%s&endtime=%s&livemode=%s",dst_request_uri,time_start,time_end,livemode);
        ngx.log(ngx.INFO, "dst_uri: " .. dst_request_uri);
    end
    if dst_request_uri ~="" and dst_request_uri ~=nil then
        dispatcher_result.dst_uri = dst_request_uri
        send_dispatcher_result(dispatcher_result);
        return true;
    end
    return false
end





local function process_cdn_cb(zone_name_list,project_id,callback,...)
    local args={...} or {}
    local client_ip = ngx.var.remote_addr
    ngx.log(ngx.INFO, "client_ip = " .. client_ip);
    local retval=false
    if #zone_name_list >0 then
        ngx.log(ngx.INFO, "ip dispatcher== " .. client_ip);
        local dst_zone = utils.ip_zones_find(project_ip_zones[project_id], client_ip);
        print(dst_zone)
        if dst_zone ~=nil  then
            local is_exist=false
            is_exist=table.foreach(zone_name_list,function(i,v) if v==dst_zone then return true  end end)
            if is_exist then
                retval=callback(unpack(args,1, table.maxn(args)))
                if retval then
                    return retval
                end
            end
        end         
    else
        retval=callback(unpack(args,1, table.maxn(args)))
        if retval then
            return retval
        end
    end
    return retval
end

local _M= {}
_M._VERSION="2.0"

---------------------------------对第三方cdn处理-------------------------------
function _M.process_third_cdn(project_area,dst_service,dst_channel,args)
    print("project_area==",project_area);
    ---------------辽宁移动
    local retval=false
    local project_id=args['p']
    if project_area == "LNYD" and liaoning_huawei_channel_list~=nil then
        ----最好独立到配置文件中
        --第三方cdn是否开启ip调度
        local zone_name_list={} 
        local retval=process_cdn_cb(zone_name_list,project_id,liaoning_huawei_processor,dst_service,liaoning_huawei_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end
    ---------------陕西移动
    if project_area == "SAXYD" and  args['apkVersion']~=nil and saxiyd_huawei_channel_list ~=nil  then
        local zone_name_list={} 
        local retval=process_cdn_cb(zone_name_list,project_id,saxiyd_huawei_processor,dst_service,saxiyd_huawei_channel_list,dst_channel,args)
        if retval then
            return retval
        end
   end
    -----云南移动华为
    if project_area == "YNYDHW" and  args['apkVersion']~=nil and ynyd_huawei_channel_list ~= nil  then
        local zone_name_list={} 
        local retval=process_cdn_cb(zone_name_list,project_id,ynyd_huawei_processor,dst_service,ynyd_huawei_channel_list,dst_channel,args)
            if retval then
                return retval
            end
    end
   -----云南移动中兴
    if project_area == "YNYDZX"  and ynyd_zhongxing_channel_list ~= nil  then
        local zone_name_list={} 
        local retval=process_cdn_cb(zone_name_list,project_id,ynyd_zhongxing_processor,dst_service,ynyd_zhongxing_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end
   ----浙江移动
    if (project_area == "ZJ_CMCC" or project_area == "ZJYD") and zhejiang_upgrage_channel_list ~= nil  then
        local zone_name_list={}
        local retval=process_cdn_cb(zone_name_list,project_id,zhejiang_yidong_huawei_processor,dst_service,zhejiang_upgrage_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end
   ---广东基地，目前服务已经停了
    if  project_area == "GDJD" and shjidi_upgrade_channel_list ~= nil then
        local zone_name_list={}
        local retval=process_cdn_cb(zone_name_list,project_id,guangdong_jidi_processor,dst_service,shjidi_upgrade_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end
   ---江苏移动华为
    if project_area == "JS_CMCC_CP"  and jiangsu_cmcc_huawei_upgrage_channel_list ~= nil and args['apkVersion']~=nil then
        local zone_name_list={}
        local retval=process_cdn_cb(zone_name_list,project_id,jiangsu_cmcc_huawei_processor,dst_service,jiangsu_cmcc_huawei_upgrage_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end


    ---江苏移动中兴
    if project_area == "JS_CMCC_CP_ZX"  and jiangsu_zhongxing_upgrage_channel_list ~= nil  then
        local zone_name_list={}
        local retval=process_cdn_cb(zone_name_list,project_id,jiangsu_cmcc_zhongxing_processor,dst_service,jiangsu_zhongxing_upgrage_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end

   

    ---武汉博远，主要是给领导们提供服务的,走江苏平台
    if project_area=='WHBY' and jiangsu_cmcc_huawei_upgrage_channel_list ~= nil and ( dst_service==live_service or dst_service==history_service) then
        local zone_name_list={}
        local retval=process_cdn_cb(zone_name_list,project_id,jiangsu_cmcc_huawei_processor,dst_service,jiangsu_cmcc_huawei_upgrage_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end

    ---河北基地
    if project_area=="HBJD" and  hbjd_channel_list_zhongxing ~= nil then
        local zone_name_list={}
        local retval=process_cdn_cb(zone_name_list,project_id,hebei_jidi_processor,dst_service,hbjd_channel_list_zhongxing,dst_channel,args)
        if retval then
            return retval
        end
    end
    ---安徽移动
    if project_area == "AH_CMCC"  and  args['apkVersion']~=nil and anhui_cmcc_upgrade_channel_list ~=nil  then
        local zone_name_list={'LANMU|CMCC_ANHUI'} 
        local retval=process_cdn_cb(zone_name_list,project_id,anhui_cmcc_processor,dst_service,anhui_cmcc_upgrade_channel_list,dst_channel,args)
        if retval then
            return retval
        end
    end
    return retval
end


local function get_ip_dispatcher_idc_zone_name(idc_zones,request_args)
    local project_id=request_args['p']
    local client_ip = ngx.var.remote_addr ;
    local dst_zone=nil
    dst_zone = utils.ip_zones_find(project_ip_zones[project_id], client_ip);
    print("ip dst zone==",dst_zone)
    if dst_zone ~=nil  then
        print(cjson.encode(idc_zones))
        for k,v in pairs(idc_zones) do
            print(v)
            if v==dst_zone then
                return dst_zone
            end
        end
    end
    return nil
end


local project_areas={
JS_CUCC        = { zone="LANMU|CUCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={'LANMU|CUCC_SUZHOU'}},
FJLT           = { zone="LANMU|CUCC_FUJIAN",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
JS_CMCC        = { zone="LANMU|CMCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
JS_CMCC_CP     = { zone="LANMU|CMCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
JS_CMCC_CP_ZX  = { zone="LANMU|CMCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
WHBY           = { zone="LANMU|CMCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
ZJ_CMCC        = { zone="LANMU|CMCC_ZHEJIANG",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
AH_CMCC        = { zone="LANMU|CMCC_ANHUI",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
BJ_CMCC        = { zone="LANMU|CMCC_BEIJING",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
GD_CMCC        = { zone="LANMU|CMCC_GUANGDONG",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
ZJYD           = { zone="LANMU|CMCC_ZHEJIANG",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
ZJYDJD         = { zone="LANMU|CMCC_ZHEJIANG",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
ZJLTJD         = { zone="LANMU|CUCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
JSLTJD         = { zone="LANMU|CUCC_JIANGSU",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
AHGD           = { zone="RADIO|ANHUI",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
SHJD           = { zone="LANMU|CMCC_ZHEJIANG",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
GDJD           = { zone="LANMU|CMCC_ZHEJIANG",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
HBJD           = { zone="LANMU|CMCC_HBJD",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
KMYD           = { zone="LANMU|CMCC_KUNMING",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
YNYDZX         = { zone="LANMU|CMCC_YNYDZX",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
YNYDHW         = { zone="LANMU|CMCC_YNYDHW",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
SAXYD          = { zone="LANMU|CMCC_SAXYD",ip_dispatcher_flag=true,ip_dispatcher_zones={}},
LNYD           = { zone="LANMU|CMCC_LIAONING",ip_dispatcher_flag=true,ip_dispatcher_zones={}}
}



function _M.get_zone_from_self_cdn(request_args)
    local project_area=request_args['area']
    print("area=="..project_area)
    local dst_zone=nil
    dst_zone=project_areas[project_area]["zone"]
    --[[zone的值为ip_lib_lanmudianbo.data 文件中的10.25.130.155/32;|LANMU|CMCC_ANHUI中的LANMU|CMCC_ANHUI,如果为空表示不需要走ip调度,如果不止一个机房
      需要把所有机房对应的zone名称配置进去
    ]]
    local ip_dispatcher_idc_zones=project_areas[project_area]["ip_dispatcher_zones"]
    local ip_dispatcher_flag = project_areas[project_area]["ip_dispatcher_flag"]
    print(cjson.encode(ip_dispatcher_idc_zones))
    if ip_dispatcher_flag and #ip_dispatcher_idc_zones>0 then
        local ip_dst_zone=get_ip_dispatcher_idc_zone_name(ip_dispatcher_idc_zones,request_args)
        print("ip dst zones=",ip_dst_zone)
        if ip_dst_zone~=nil then
            return ip_dst_zone
        end
    end
    ngx.log(ngx.INFO, "dst_zone: " .. dst_zone);
    return dst_zone
end



return _M
