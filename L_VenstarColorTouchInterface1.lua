-- -----------------------------------------------------------------------------
-- L_VenstarColorTouchInterface.lua
-- Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved
-- http://www.toggledbits.com/venstar/
-- This file is available under GPL 3.0. See LICENSE in documentation for info.
-- -----------------------------------------------------------------------------

module("L_VenstarColorTouchInterface1", package.seeall)

local math = require("math")
local string = require("string")
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("dkjson")

local _PLUGIN_NAME = "VenstarColorTouchInterface"
local _PLUGIN_VERSION = "1.0develop180816.1020"
local _PLUGIN_URL = "http://www.toggledbits.com/venstar"
local _CONFIGVERSION = 010000

local debugMode = true
local traceMode = true

local MYSID = "urn:toggledbits-com:serviceId:VenstarColorTouchInterface1"
local MYTYPE = "urn:schemas-toggledbits-com:device:VenstarColorTouchInterface:1"

local DEVICESID = "urn:toggledbits-com:serviceId:VenstarColorTouchThermostat1"
local DEVICETYPE = "urn:schemas-toggledbits-com:device:VenstarColorTouchThermostat:1"

local OPMODE_SID = "urn:upnp-org:serviceId:HVAC_UserOperatingMode1"
local FANMODE_SID = "urn:upnp-org:serviceId:HVAC_FanOperatingMode1"
local STATUS_SID = "urn:micasaverde-com:serviceId:HVAC_OperatingState1"
local SETPOINT_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1"
local SETPOINT_HEAT_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat"
local SETPOINT_COOL_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1_Cool"
local TEMPSENS_SID = "urn:upnp-org:serviceId:TemperatureSensor1"
local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"

local MODE_OFF = "Off"
local MODE_COOL = "CoolOn"
local MODE_HEAT = "HeatOn"
local MODE_AUTO = "AutoChangeOver"

local EMODE_NORMAL = "Normal"
-- local EMODE_ECO = "EnergySavingsMode"

local FANMODE_AUTO = "Auto"
-- local FANMODE_PERIODIC = "PeriodicOn"
local FANMODE_ON = "ContinuousOn"

-- Default refresh interval. This can be overridden by state variable RefreshInterval
local DEFAULT_REFRESH = 60

local pluginDevice
local runStamp = {}
local devData = {}
local devicesByMAC = {}

local isALTUI = false
local isOpenLuup = false

local function trace( typ, msg )
    local ts = os.time()
    local r
    local t = {
        ["type"]=typ,
        plugin=__PLUGIN_NAME or "unknown",
        pluginVersion=_CONFIGVERSION,
        serial=luup.pk_accesspoint,
        loadtime=luup.attr_get("LoadTime", 0),
        systime=ts,
        sysver=luup.version,
        longitude=luup.longitude,
        latitude=luup.latitude,
        timezone=luup.timezone,
        city=luup.city,
        isALTUI=isALTUI,
        isOpenLuup=isOpenLuup,
        message=msg
    }

    local tHeaders = {}
    local body = json.encode(t)
    tHeaders["Content-Type"] = "application/json"
    tHeaders["Content-Length"] = string.len(body)

    -- Make the request.
    local respBody, httpStatus, httpHeaders
    http.TIMEOUT = 10
    respBody, httpStatus, httpHeaders = http.request{
        url = "https://www.toggledbits.com/luuptrace/",
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(r),
        method = "POST",
        headers = tHeaders,
        redirect = false
    }
    if httpStatus == 401 or httpStatus == 404 then
        traceMode = false
    end
    if httpStatus == 404 then
        luup.variable_set(SID, "TraceMode", 0, myDevice)
    end
end

local function dump(t)
    if t == nil then return "nil" end
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
        local val
        if type(v) == "table" then
            val = dump(v)
        elseif type(v) == "function" then
            val = "(function)"
        elseif type(v) == "string" then
            val = string.format("%q", v)
        elseif type(v) == "number" then
            local d = v - os.time()
            if d < 0 then d = -d end
            if d <= 86400 then
                val = string.format("%d (%s)", v, os.date("%X", v))
            else
                val = tostring(v)
            end
        else
            val = tostring(v)
        end
        str = str .. sep .. k .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...)
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg["prefix"] or "") .. (msg["msg"] or "")
        level = msg["level"] or level
    else
        str = _PLUGIN_NAME .. ": " .. msg
    end
    str = string.gsub(str, "%%(%d+)", function( n )
            n = tonumber(n, 10)
            if n < 1 or n > #arg then return "nil" end
            local val = arg[n]
            if type(val) == "table" then
                return dump(val)
            elseif type(val) == "string" then
                return string.format("%q", val)
            elseif type(val) == "number" then
                local d = val - os.time()
                if d < 0 then d = -d end
                if d <= 86400 then
                    val = string.format("%d (time %s)", val, os.date("%X", val))
                end
            end
            return tostring(val)
        end
    )
    luup.log(str, level)
    if traceMode then trace('log',str) end
end

local function D(msg, ...)
    if debugMode then
        L({msg=msg,prefix=_PLUGIN_NAME.."(debug)::"}, ... )
    end
end

-- Initialize a variable to a default value if it doesn't already exist.
local function initVar( sid, var, defaultVal, dev )
    local oldVal = luup.variable_get( sid, var, dev )
    if oldVal == nil then
        luup.variable_set( sid, var, defaultVal, dev )
        return defaultVal
    end
    return oldVal
end

-- Set a state variable only if its value has changed
local function setVar( sid, var, val, dev )
    local oldVal = luup.variable_get( sid, var, dev )
    if oldVal ~= val then
        luup.variable_set( sid, var, val, dev )
    end
end

local function split( str, sep )
    if sep == nil then sep = "," end
    local arr = {}
    if #str == 0 then return arr, 0 end
    local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
    table.insert( arr, rest )
    return arr, #arr
end

-- Constraint the argument to the specified min/max
local function constrain( n, nMin, nMax )
    n = tonumber(n, 10) or nMin
    if n < nMin then return nMin end
    if nMax ~= nil and n > nMax then return nMax end
    return n
end

-- Convert F to C
local function FtoC( temp )
    temp = tonumber(temp, 10)
    assert( temp ~= nil )
    return ( temp - 32 ) * 5 / 9
end

-- Convert C to F
local function CtoF( temp )
    temp = tonumber(temp, 10)
    assert( temp ~= nil )
    return ( temp * 9 / 5 ) + 32
end

-- Convert between units if needed.
local function convertTemp( inputTemp, inputUnits, outputUnits )
    D("convertTemp(%1,%2,%3)", inputTemp, inputUnits, outputUnits)
    if inputUnits == "C" and outputUnits == "F" then
        inputTemp = CtoF( inputTemp )
    elseif inputUnits == "F" and outputUnits == "C" then
        inputTemp = FtoC( inputTemp )
    end
    return inputTemp
end

local function askLuci(p)
    D("askLuci(%1)", p)
    local uci = require("uci")
    if uci then
        local ctx = uci.cursor(nil, "/var/state")
        if ctx then
            return ctx:get(unpack((split(p,"%."))))
        else
            D("askLuci() can't get context")
        end
    else
        D("askLuci() no UCI module")
    end
    return nil
end

-- Query UCI for WAN IP4 IP
local function getSystemIP4Addr( dev )
    local vera_ip = askLuci("network.wan.ipaddr")
    D("getSystemIP4Addr() got %1 from Luci", vera_ip)
    if not vera_ip then
        -- Fallback method
        local p = io.popen("/usr/bin/GetNetworkState.sh wan_ip")
        vera_ip = p:read("*a") or ""
        p:close()
        D("getSystemIP4Addr() got system ip4addr %1 using fallback", vera_ip)
    end
    return vera_ip:gsub("%c","")
end

-- Query UCI for WAN IP4 netmask
local function getSystemIP4Mask( dev )
    local mask = askLuci("network.wan.netmask");
    D("getSystemIP4Mask() got %1 from Luci", mask)
    if not mask then
        -- Fallback method
        local p = io.popen("/usr/bin/GetNetworkState.sh wan_netmask")
        mask = p:read("*a") or ""
        p:close()
        D("getSystemIP4Addr() got system ip4mask %1 using fallback", mask)
    end
    return mask:gsub("%c","")
end

-- Compute broadcast address (IP4)
local function getSystemIP4BCast( dev )
    local broadcast = luup.variable_get( MYSID, "DiscoveryBroadcast", dev ) or ""
    if broadcast ~= "" then
        return broadcast
    end

    -- Do it the hard way.
    local vera_ip = getSystemIP4Addr( dev )
    local mask = getSystemIP4Mask( dev )
    D("getSystemIP4BCast() sys ip %1 netmask %2", vera_ip, mask)
    local a1,a2,a3,a4 = vera_ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)")
    local m1,m2,m3,m4 = mask:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)")
    local bit = require("bit")
    -- Yeah. This is my jam, baby!
    a1 = bit.bor(bit.band(a1,m1), bit.bxor(m1,255))
    a2 = bit.bor(bit.band(a2,m1), bit.bxor(m2,255))
    a3 = bit.bor(bit.band(a3,m3), bit.bxor(m3,255))
    a4 = bit.bor(bit.band(a4,m4), bit.bxor(m4,255))
    broadcast = string.format("%d.%d.%d.%d", a1, a2, a3, a4)
    D("getSystemIP4BCast() computed broadcast address is %1", broadcast)
    return broadcast
end

local function scanARP( dev, mac, ipaddr )
    D("scanARP(%1,%2,%3)", dev, mac, ipaddr)

    -- Vera arp is a function defined in /etc/profile (currently). ??? Needs some flexibility here.
    local pipe = io.popen("cat /proc/net/arp")
    local m = pipe:read("*a")
    pipe:close()
    local res = {}
    m:gsub("([^\r\n]+)", function( t )
            local p = { t:match("^([^%s]+)%s+([^%s]+)%s+([^%s]+)%s+([^%s]+)%s+(.*)$") }
            -- D("scanARP() handling line %1, data %2", t, p)
            if p ~= nil and p[4] ~= nil then
                local mm = p[4]:gsub("[:-]", ""):upper() -- clean MAC
                if ( mac or "" ) ~= "" then
                    if mm == mac then
                        table.insert( res, { mac=mac, ip=p[1] } )
                    end
                elseif ( ipaddr or "" ) ~= "" then
                    if ipaddr == p[1] and mm ~= "000000000000" then
                        table.insert( res, { mac=mm, ip=ipaddr } )
                    end
                end
            end
            return ""
        end
    )
    D("scanARP() result is %1", res)
    return res
end

-- Try to resolve a MAC address to an IP address. We do with with a broadcast ping
-- followed by an examination of the ARP table.
local function getIPforMAC( mac, dev )
    D("getIPforMAC(%1,%2)", mac, dev)
    assert(not isOpenLuup, "We don't know how to do this on openLuup, yet.")
    mac = mac:gsub("[%s:-]", ""):upper()
    local broadcast = getSystemIP4BCast( dev )
    os.execute("/bin/ping -4 -q -c 3 -w 1 " .. broadcast)
    return scanARP( dev, mac, nil )
end

-- Try to resolve IP address to a MAC address. Same process as above.
local function getMACforIP( ipaddr, dev )
    D("getMACforIP(%1,%2)", ipaddr, dev)
    if debugMode and isOpenLuup then return { { mac="74:D4:35:16:50:DE", ip=ipaddr } } end -- ???
    assert(not isOpenLuup, "We don't know how to do this on openLuup, yet.")
    os.execute("/bin/ping -4 -q -c 3 " .. ipaddr)
    return scanARP( dev, nil, ipaddr )
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, serviceId )
    assert(name ~= nil)
    assert(dev ~= nil)
    if debugMode then assert(serviceId ~= nil) end
    if serviceId == nil then serviceId = MYSID end
    local s = luup.variable_get(serviceId, name, dev)
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

-- Get "current" setpoint. We attempt to discern this by tracking the last
-- state of the thermostat.
local function getCurrentSetpoint( dev )
    local last = luup.variable_get( DEVICESID, "CurrentSetpoint", dev ) or "Heating"
    if last == "Cooling" then
        return getVarNumeric( "CurrentSetpoint", devData[tostring(dev)].sysinfo.maxCoolTemp, dev, SETPOINT_COOL_SID )
    end
    return getVarNumeric( "CurrentSetpoint", devData[tostring(dev)].sysinfo.minHeatTemp, dev, SETPOINT_HEAT_SID )
end

-- Set gateway status display. Also echos message to log.
local function gatewayStatus( msg )
    msg = msg or ""
    if msg ~= "" then L(msg) end -- don't clear clearing of status
    luup.variable_set( MYSID, "DisplayStatus", msg, pluginDevice )
end

-- Find WMP device by MAC address
local function findDeviceByMAC( mac )
    D("findDeviceByMAC(%1,%2)", mac)
    mac = (mac or ""):upper()
    -- Cached?
    if devicesByMAC[mac] ~= nil then return devicesByMAC[mac], luup.devices[devicesByMAC[mac]] end
    -- No, look for it.
    for n,d in pairs(luup.devices) do
        if d.device_type == DEVICETYPE and d.device_num_parent == pluginDevice and mac == d.id then
            devicesByMAC[mac] = n
            return n,d
        end
    end
    return nil
end

-- Return an array of the Luup device numbers of all child WMP devices of parent
local function inventoryChildren()
    local children = {}
    for n,d in pairs( luup.devices ) do
        if d.device_type == DEVICETYPE and d.device_num_parent == pluginDevice then
            devicesByMAC[d.id] = n -- fast-track our cache of known children
            table.insert( children, n )
        end
    end
    return children
end

local function doRequest(method, url, tHeaders, body, dev)
    D("doRequest(%1,%2,%3,%4,%5)", method, url, tHeaders, body, dev)
    assert(dev ~= nil)
    method = method or "GET"
    tHeaders = tHeaders or {}

    -- A few other knobs we can turn
    local timeout = getVarNumeric("Timeout", 30, dev, DEVICESID) -- ???
    -- local maxlength = getVarNumeric("MaxLength", 262144, dev, DEVICESID) -- ???

    -- Build post/put data
    local src
    if type(body) == "table" then
        body = json.encode(body)
        tHeaders["Content-Type"] = "application/json"
    end
    if (body or "") ~= "" then
        -- Caller should set Content-Type
        tHeaders["Content-Length"] = string.len(body)
        src = ltn12.source.string(body)
    else
        src = nil
    end

    -- Make the request.
    local respBody, httpStatus
    local r = {}
    http.TIMEOUT = timeout -- N.B. http not https, regardless
    D("doRequest() %2 %1, headers=%3", url, method, tHeaders)
    respBody, httpStatus = http.request{
        url = url,
        source = src,
        sink = ltn12.sink.table(r),
        method = method,
        headers = tHeaders,
        redirect = false
    }
    D("doRequest() request returned httpStatus=%1, respBody=%2", httpStatus, respBody)

    -- Since we're using the table sink, concatenate chunks to single string.
    respBody = table.concat(r)

    D("doRequest() response HTTP status %1, body=" .. respBody, httpStatus) -- use concat to avoid quoting

    -- Handle special errors from socket library
    if tonumber(httpStatus) == nil then
        respBody = httpStatus
        httpStatus = 500
    end

    -- See what happened. Anything 2xx we reduce to 200 (OK).
    if httpStatus >= 200 and httpStatus <= 299 then
        -- Success response with no data, take shortcut.
        return true, respBody, 200
    end
    return false, respBody, httpStatus
end


-- Make a request
local function request( rtype, path, rhead, body, dev )
    D("request(%1,%2,%3,%3,%4,%5)", rtype, path, rhead, body, dev)
    local url = ( luup.variable_get( DEVICESID, "APIPath", dev ) or "http://127.0.0.1:8080" ) .. path
    local success, respbody, httpStatus = doRequest( rtype, url, rhead, body, dev )
    if success then
        local data,pos,err = json.decode( respbody )
        if not err then
            return true, data
        end
        D("request() unable to parse JSON response, %1 at %2 in %3", err, pos, respbody)
        return false
    end
    D("request() device request error, httpStatus=%1", httpStatus)
    return false
end

-- Do an info query from the ColorTouch API
local function doInfoQuery( dev )
    local cfUnits = luup.variable_get( DEVICESID, "ConfiguredUnits", dev ) or "F"
    local dk = tostring(dev)
    local success, data = request( "GET", "/query/info", nil, nil, dev )
    if success then
        if data.tempunits ~= nil then
            -- 0=F, 1=C. Note that if this changes, we reconfigure.
            local tUnits = ( data.tempunits == 0 ) and "F" or "C"
            devData[dk].sysinfo.units = tUnits
            if tUnits ~= cfUnits then
                -- Reset configuration for temperature units configured.
                L("Reconfiguring %1 (%2) from degrees %1 to %2, which will require a Luup restart.", 
                    luup.devices[dev].description, dev, cfUnits, tUnits)
                luup.variable_set( DEVICESID, "ConfiguredUnits", tUnits, dev )
                luup.attr_set( "device_json", "D_VenstarColorTouchThermostat1_" .. tUnits .. ".json", dev )
                luup.reload()
            end
        end
        if data.mode ~= nil then
            local xmap = { [0]=MODE_OFF, [1]=MODE_HEAT, [2]=MODE_COOL, [3]=MODE_AUTO }
            setVar( OPMODE_SID, "ModeStatus", xmap[data.mode] or "Unknown", dev )
            if data.mode == 1 or data.mode == 2 then
                setVar( DEVICESID, "CurrentSetpoint", (data.mode==1) and "Heating" or "Cooling", dev )
            end
        end
        if data.state ~= nil then
            local state = ({ [0]="Idle", [1]="Heating", [2]="Cooling", [3]="Lockout", [4]="Error" })[data.state] or "Unknown"
            if data.state == 0 and ( data.fanstate or 0 ) ~= 0 then state = "FanOnly" end
            setVar( STATUS_SID, "ModeState", state, dev )
            if data.state == 1 or data.state == 2 then
                setVar( DEVICESID, "CurrentSetpoint", state, dev )
            end
        end
        if data.fan ~= nil then
            local xmap = { [1]=FANMODE_ON }
            setVar(FANMODE_SID, "Mode", xmap[data.fan] or FANMODE_AUTO, dev)
        end
        if data.fanstate ~= nil then
            setVar(FANMODE_SID, "FanStatus", ( data.fanstate ~= 0 ) and "On" or "Off", dev)
        end
        if data.schedule ~= nil then
        end
        if data.schedulepart ~= nil then
        end
        if data.away ~= nil then
            luup.variable_set( DEVICESID, "HomeAwayMode", ( data.away == 0 ) and "Home" or "Away", dev )
        end
        if data.holiday ~= nil then
            -- commercial only
        end
        if data.override ~= nil then
            -- commercial only
            -- overridetime
        end
        if data.forceunocc ~= nil then
            -- commercial only
        end
        if data.spacetemp ~= nil then
            setVar( TEMPSENS_SID, "CurrentTemperature", string.format( "%.1f", data.spacetemp ), dev )
        end
        if data.heattemp ~= nil then
            setVar( SETPOINT_HEAT_SID, "CurrentSetpoint", data.heattemp, dev )
        end
        if data.cooltemp ~= nil then
            setVar( SETPOINT_COOL_SID, "CurrentSetpoint", data.cooltemp, dev )
        end
        if data.cooltempmin ~= nil then
            devData[dk].sysinfo.minCoolTemp = data.cooltempmin
        end
        if data.cooltempmax ~= nil then
            devData[dk].sysinfo.maxCoolTemp = data.cooltempmax
        end
        if data.heattempmin ~= nil then
            devData[dk].sysinfo.minHeatTemp = data.heattempmin
        end
        if data.heattempmax ~= nil then
            devData[dk].sysinfo.maxHeatTemp = data.heattempmax
        end
        if data.setpointdelta ~= nil then
            devData[dk].sysinfo.delta = data.setpointdelta
        end
        if data.hum ~= nil then
            setVar( "urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", tostring(data.hum), dev )
        end
        if data.availablemodes ~= nil then
            if data.availablemodes == 0 then
                -- All modes
                devData[dk].sysinfo.hasModes = { [MODE_HEAT]=true, [MODE_COOL]=true, [MODE_AUTO]=true }
            elseif data.availablemodes == 1 then
                -- Heat only
                devData[dk].sysinfo.hasModes = { [MODE_HEAT]=true }
            elseif data.availablemodes == 2 then
                -- Cool only
                devData[dk].sysinfo.hasModes = { [MODE_COOL]=true }
            elseif data.availablemodes == 3 then
                -- Heat/cool only
                devData[dk].sysinfo.hasModes = { [MODE_HEAT]=true, [MODE_COOL]=true }
            end
            -- Can always do "OFF"
            devData[dk].sysinfo.hasModes[MODE_OFF]=true
        end
        
        -- Save it
        luup.variable_set( DEVICESID, "sysinfo", json.encode( devData[dk].sysinfo ), dev )
    end
    return success
end

-- Update the display status. We don't really bother with this at the moment because the WMP
-- protocol doesn't tell us the running status of the unit (see comments at top of this file).
local function updateDeviceStatus( dev )
    local cfUnits = luup.variable_get( DEVICESID, "ConfiguredUnits", dev ) or "F"
    local failed = getVarNumeric( "Failure", 0, dev, DEVICESID )
    if failed ~= 0 then
        luup.variable_set( DEVICESID, "DisplayStatus", "Offline", dev )
        luup.variable_set( DEVICESID, "DisplayTemperature", "--.-&deg;"..cfUnits, dev )
    else
        local msg = luup.variable_get( STATUS_SID, "ModeState", dev ) or "Unknown"
        luup.variable_set( DEVICESID, "DisplayStatus", msg, dev )
        local temp = luup.variable_get( TEMPSENS_SID, "CurrentTemperature", dev ) or "--.-"
        luup.variable_set( DEVICESID, "DisplayTemperature", string.format( "%s&deg;%s", temp, cfUnits ), dev )
    end
end

-- Handle a discovery response.
local function handleDiscoveryMessage( msg )
    D("handleDiscoveryMessage(%1)", msg)

    --[[ Message format expected:
         HTTP/1.1 200 OK
         Cache-Control: max-age=300
         ST: colortouch:ecp
         Location: http://192.168.1.100:8080/
         USN: ecp:00:23:a7:3a:b2:72:name:Living%20Room
    --]]

    local parts = split( msg, "[\r\n]+" )
    parts[1] = parts[1] or ""
    if not string.match( parts[1], "^HTTP/1.1 200 OK" ) then
        D("handleDiscoveryMessage() can't handle message header: %1", msg)
        return
    end
    table.remove( parts, 1 ) -- pop response type off
    local hr = {}
    for _,l in ipairs( parts ) do
        local k,v = string.match( l or "", "^(%w+):%s*(.*)$" )
        if k then
            hr[string.lower(k)] = v
            D("handleDiscoveryMessage() response header %1 is %2", string.lower(k), v)
        end
    end
    if hr.st == nil or hr.st ~= "colortouch:ecp" then
        D("handleDiscoveryMessage() message is not for colortouch: %1", msg)
        return
    end
    if hr.location == nil or hr.usn == nil then
        L({level=2,msg="Malformed or unrecognized discovery response: %1"}, msg)
        return
    end
    local api_url = hr.location or "http://127.0.0.1:8080/"
    local mac,name = string.match( hr.usn or "", "ecp:(..:..:..:..:..:..):name:(.*)" ) -- ??? parse better?
    if mac == nil then
        D("handleDiscoveryMessage() can't parse USN %1", hr.usn )
        return
    end
    
    mac = string.gsub( mac, ":", "" )
    -- URLdecode name, supply default
    name = string.gsub( name or "", "%%(..)", function( x ) return string.char( tonumber(x,16) ) end )
    if ( name or "" ) == "" then name = "ColorTouch " .. string.sub( mac, -6 ) end

    L("Discovery response from %1 name %2", mac, name)

    -- See if the device is already listed
    local child = findDeviceByMAC( mac )
    if child ~= nil then
        gatewayStatus( string.format("%s (%s) is already known", mac, name ) )
        luup.variable_set( DEVICESID, "APIPath", api_url, child )
        return
    end

    -- Need to create a child device, which can only be done by re-creating all child devices.
    gatewayStatus( string.format("Adding %s (%s)...", mac, name ) )

    local children = inventoryChildren()
    local ptr = luup.chdev.start( pluginDevice )
    for _,ndev in ipairs( children ) do
        local v = luup.devices[ndev]
        D("adding child %1 (%2)", v.id, v.description)
        luup.chdev.append( pluginDevice, ptr, v.id, v.description, "", "D_VenstarColorTouchThermostat1.xml", "", "", false )
    end

    -- Now add newly discovered device
    L("Adding new thermostat %1 (%2)", mac, name)
    luup.chdev.append( pluginDevice, ptr,
        mac, -- id (altid)
        name, -- description
        "", -- device type
        "D_VenstarColorTouchThermostat1.xml", -- device file
        "", -- impl file
        DEVICESID .. ",APIPath=" .. api_url, -- state vars
        false -- embedded
    )

    -- Close children. This will cause a Luup reload if something changed.
    luup.chdev.sync( pluginDevice, ptr )
    L("Children done. Reload coming!")
end

-- Fake a discovery message with the MAC and IP passed.
local function passGenericDiscovery( mac, ip, port, dev )
    D("passGenericDiscovery(%1,%2,%3,%4)", mac, ip, port, dev)
    mac = string.gsub( mac or "", "[%.:-]", "" ) -- remove various delimiters
    local nn = "ColorTouch " .. string.sub(mac, -6)
    mac = string.gsub( mac, "(..)(..)(..)(..)(..)(..)", "%1:%2:%3:%4:%5:%6" )
    handleDiscoveryMessage(
        string.format("HTTP/1.1 200 OK\r\nCache-Control: max-age=300\r\nST: colortouch:ecp\r\nLocation: http://%s:%s\r\nUSN: ecp:%s:name:%s", ip, tostring(port), mac, nn),
        gateway )
end

function deviceTick( dargs )
    D("deviceTick(%1), luup.device=%2", dargs, luup.device)
    local dev, stamp = dargs:match("^(%d+):(%d+):(.*)$")
    dev = tonumber(dev, 10)
    assert(dev ~= nil, "Nil device in deviceTick()")
    stamp = tonumber(stamp, 10)
    if stamp ~= runStamp[dev] then
        D("deviceTick() received stamp %1, expecting %2; must be a newer thread started, exiting.", stamp, runStamp[dev])
        return
    end

    -- Set up for next update
    local nextDelay = getVarNumeric( "RefreshInterval", DEFAULT_REFRESH, dev, DEVICESID )

    -- See if we received any data.
    local status, result = pcall( doInfoQuery, dev )
    if not ( status and result ) then
        luup.variable_set( DEVICESID, "Failure", 1, dev )
        if not status then
            L({level=1,msg="Update tick failed: %1"}, result)
        else
            L({level=2,msg="%1 (%2) is not responding to queries."}, luup.devices[dev].description, dev)
        end
    elseif getVarNumeric( "Failure", 0, dev, DEVICESID ) ~= 0 then
        luup.variable_set( DEVICESID, "Failure", 0, dev )
    end

    -- Arm for another query.
    assert( nextDelay > 0 )
    D("deviceTick(%1) arming for next tick in %2", dargs, nextDelay)
    luup.call_delay( "venstarCTDeviceTick", nextDelay, dargs )
end

-- Do a one-time startup on a new device
local function deviceRunOnce( dev )

    local rev = getVarNumeric("Version", 0, dev, DEVICESID)
    if (rev == 0) then
        -- Initialize for new installation
        D("deviceRunOnce() Performing first-time initialization!")
        -- APIPath should have been set during child creation
        initVar(DEVICESID, "APIPath", "", dev)
        initVar(DEVICESID, "DisplayTemperature", "--.-", dev)
        initVar(DEVICESID, "DisplayStatus", "", dev)
        initVar(DEVICESID, "ConfiguredUnits", "F", dev)
        initVar(DEVICESID, "CurrentSetpoint", "Heating", dev)
        initVar(DEVICESID, "HomeAwayMode", "Home", dev)
        initVar(DEVICESID, "Failure", 0, dev )

        initVar(OPMODE_SID, "ModeTarget", MODE_OFF, dev)
        initVar(OPMODE_SID, "ModeStatus", MODE_OFF, dev)
        initVar(OPMODE_SID, "EnergyModeTarget", EMODE_NORMAL, dev)
        initVar(OPMODE_SID, "EnergyModeStatus", EMODE_NORMAL, dev)
        initVar(OPMODE_SID, "AutoMode", "1", dev)

        initVar(FANMODE_SID, "Mode", FANMODE_AUTO, dev)
        initVar(FANMODE_SID, "FanStatus", "Off", dev)

        -- Setpoint defaults. Note that we don't have sysinfo yet during this call.
        initVar(SETPOINT_SID, "Application", "DualHeatingCooling", dev)
        initVar(SETPOINT_SID, "SetpointAchieved", "0", dev)
        if luup.attr_get("TemperatureFormat",0) == "C" then
            initVar(SETPOINT_HEAT_SID, "CurrentSetpoint", "22", dev)
            initVar(SETPOINT_COOL_SID, "CurrentSetpoint", "22", dev)
        else
            initVar(SETPOINT_HEAT_SID, "CurrentSetpoint", "72", dev)
            initVar(SETPOINT_COOL_SID, "CurrentSetpoint", "72", dev)
        end

        initVar(STATUS_SID, "ModeState", "Idle", dev )

        initVar(HADEVICE_SID, "ModeSetting", "1:;2:;3:;4:", dev)

        luup.variable_set(DEVICESID, "Version", _CONFIGVERSION, dev)
        return
    end
--]]

    -- No matter what happens above, if our versions don't match, force that here/now.
    if (rev ~= _CONFIGVERSION) then
        luup.variable_set(DEVICESID, "Version", _CONFIGVERSION, dev)
    end
end

-- Do startup of a child device
local function deviceStart( dev )
    D("deviceStart(%1)", dev )

    -- Make sure the device is initialized. It may be new.
    deviceRunOnce( dev )

    -- Early inits
    local dk = tostring(dev)
    devData[dk] = {}
    local s = luup.variable_get( DEVICESID, "sysinfo", dev ) or ""
    if s ~= "" then
        local data,pos,err = json.decode( s )
        if not err then
            devData[dk].sysinfo = data
        end
    end
    if devData[dk].sysinfo == nil then
        local cfUnits = luup.variable_get( DEVICESID, "ConfiguredUnits", dev ) or "F"
        devData[dk].sysinfo = { units=cfUnits, delta=2.0, minHeatTemp=55, maxHeatTemp=95, minCoolTemp=55, maxCoolTemp=95,
            hasModes={ [MODE_OFF]=true, [MODE_HEAT]=true, [MODE_COOL]=true, [MODE_AUTO]=true }
        }
    end

    -- Innocent until proven guilty.
    luup.variable_set( DEVICESID, "Failure", 0, dev )

    -- A few things we care to keep an eye on.
    luup.variable_watch( "venstarCTVarChanged", DEVICESID, "Failure", dev )
    luup.variable_watch( "venstarCTVarChanged", STATUS_SID, "ModeState", dev )
    luup.variable_watch( "venstarCTVarChanged", TEMPSENS_SID, "CurrentTemperature", dev )

    -- Schedule first tick on this device.
    runStamp[dev] = os.time() - math.random(1, 100000)
    luup.call_delay( "venstarCTDeviceTick", dev % 10, table.concat( { dev, runStamp[dev], "" }, ":" )) -- must provide 3 dargs

    updateDeviceStatus( dev )

    L("Device %1 started!", dev)
    luup.set_failure( 0, dev )
    return true, "OK", luup.devices[dev].description
end

local function discoveryByMAC( mac, dev )
    D("discoveryByMAC(%1,%2)", mac, dev)
    local port = 80 -- ??? use :port like IP?
    gatewayStatus( "Searching for " .. mac )
    local res = getIPforMAC( mac, dev )
    if res ~= nil then
        local first = res[1]
        D("discoveryByMAC() found IP %1 for MAC %2", first.ip, first.mac)
        gatewayStatus( "Contacting " .. first.ip )
        local status,body,httpStatus = doRequest( "GET", string.format("http://%s:%d/", first.ip, port), {}, nil, dev )
        D("discoveryByMAC() response from %1 %2 is %3", first.ip, httpStatus, body)
        if status then
            local data,_,err = json.decode( body )
            D("discoveryByMAC() json %1: %2", err, data)
            if not err and data.api_ver ~= nil then
                D("discoveryByMAC() valid response from %2 (%1)", first.mac, first.ip)
                gatewayStatus( "Registering thermostat" )
                passGenericDiscovery( first.mac, first.ip, port, dev )
                return
            else
                gatewayStatus( "Not ColorTouch thermostat" )
                L({level=1,msg="Device at %1 did not respond as a ColorTouch thermostat"}, first.ip)
                return
            end
        else
            gatewayStatus( "Refused by " .. first.ip )
            L({level=1,msg="Device at %1 could not be queried, may not be ColorTouch thermostat or 'Local API' not enabled in its settings"}, first.ip)
            return
        end
    end
    L({level=1,msg="Could not ARP %1 for discovery. Please make sure the device is up on the LAN"}, mac)
    gatewayStatus( "Device not found with MAC " .. mac )
    return false
end

-- Try to ping the device, and then find its MAC address in the ARP table.
local function discoveryByIP( ipp, dev )
    D("discoveryByIP(%1,%2)", ipp, dev)
    local ipaddr,port = string.match( ipp, "^([^:]+):(%d+)" )
    if ipaddr ~= nil then
        port = tonumber(port) or 80
    else
        ipaddr = ipp
        port = 80
    end
    gatewayStatus( "Contacting " .. ipp )
    local res = getMACforIP( ipaddr, dev )
    if res ~= nil then
        local first = res[1]
        local status,body,httpStatus = doRequest( "GET", string.format("http://%s:%d/", ipaddr, port), {}, nil, dev )
        D("discoveryByIP() response from %1 %2 is %3", ipp, httpStatus, body)
        if status then
            local data,_,err = json.decode( body )
            D("discoveryByIP() json %1: %2", err, data)
            if not err and data.api_ver ~= nil then
                D("discoveryByIP() found MAC %1 for IP %2", first.mac, first.ip)
                gatewayStatus( "Registering thermostat" )
                passGenericDiscovery( first.mac, first.ip, port, dev )
                return
            else
                gatewayStatus( "Not ColorTouch thermostat" )
                L({level=1,msg="Device at %1 did not respond as a ColorTouch thermostat"}, ipaddr)
                return
            end
        else
            gatewayStatus( "Not ColorTouch thermostat" )
            L({level=1,msg="Device at %1 could not be queried, may not be ColorTouch thermostat or 'Local API' not enabled in its settings"}, ipaddr)
            return
        end
    end
    L({level=1,msg="Could not RARP %1 for discovery. Please make sure the device is up on the LAN"}, ipaddr)
    gatewayStatus( "Search failed" )
end

-- Tick for UDP discovery.
function discoveryTick( dargs )
    D("discoveryTick(%1)", dargs)
    local dev, stamp = dargs:match("^(%d+):(%d+):(.*)$") -- ignore rest
    dev = tonumber(dev, 10)
    assert(dev ~= nil)
    assert(luup.devices[dev].device_num_parent == 0)
    stamp = tonumber(stamp, 10)
    if stamp ~= runStamp[dev] then
        L("discoveryTick() got stamp %1 expected %2; must be newer thread running, exiting", stamp, runStamp[dev])
        return
    end

    gatewayStatus( "Discovery running..." )

    local udp = devData[tostring(dev)].discoverySocket
    if udp ~= nil then
        repeat
            udp:settimeout(1)
            local resp, peer, port = udp:receivefrom()
            if resp ~= nil then
                D("discoveryTick() received response from %1:%2", peer, port)
                handleDiscoveryMessage( resp, dev )
            end
        until resp == nil

        local now = os.time()
        local delta = now - devData[tostring(dev)].discoveryTime
        if delta < 30 then
            luup.call_delay( "venstarCTDiscoveryTick", 2, dargs )
            return
        end
        D("discoveryTick() elapsed %1, closing", delta)
        udp:close()
        devData[tostring(dev)].discoverySocket = nil
        devData[tostring(dev)].discoveryTime = nil
    end
    D("discoveryTick() end of discovery")
    gatewayStatus( "" )
end

-- Launch UDP discovery.
local function launchDiscovery( dev )
    D("launchDiscovery(%1)", dev)
    assert(dev ~= nil)
    assert(luup.devices[dev].device_type == MYTYPE, "Discovery much be launched with gateway device")

    gatewayStatus( "Discovery running..." )

    -- Any of this can fail, and it's OK.
    local udp = socket.udp()
    local broadcast = "239.255.255.250"
    local port = 1900
    udp:setoption('broadcast', true)
    udp:setoption('dontroute', false) -- Important! =false
    -- udp:setsockname('*', port) -- Important! =comment out
    D("launchDiscovery() sending discovery request to %1:%2", broadcast, port)
    local stat,err = udp:sendto( "M-SEARCH * HTTP/1.1\r\nHost: " .. broadcast .. ":" .. port ..
        "\r\nMan: \"ssdp:discover\"\r\nST: colortouch:ecp\r\n\r\n", broadcast, port)
    if stat == nil then
        L("Failed to send broadcast: %1", err)
    end

    devData[tostring(dev)].discoverySocket = udp
    local now = os.time()
    devData[tostring(dev)].discoveryTime = now

    runStamp[dev] = now
    luup.call_delay("venstarCTDiscoveryTick", 1, table.concat( { dev, runStamp[dev], "" }, ":") ) -- 3 dargs
end

-- Handle variable change callback
function varChanged( dev, sid, var, oldVal, newVal )
    D("varChanged(%1,%2,%3,%4,%5)", dev, sid, var, oldVal, newVal)
    -- assert(var ~= nil) -- nil if service or device watch (can happen on openLuup)
    updateDeviceStatus( dev )
end

local function forceUpdate( dev )
    D("forceUpdate(%1)", dev)
    runStamp[dev] = os.time()
    luup.call_delay( "venstarCTDeviceTick", 5, table.concat( { dev, runStamp[dev], "" }, ":" ) )
end

local function doControl( body, dev )
    D("doControl(%1,%2)", body, dev)
    local status, resp = request( "POST", "/control", { ['Content-Type']="application/x-www-form-urlencoded" }, body, dev )
    D("doControl() response status %1 data %2", status, resp)
    if status then
        if resp.error then
            luup.variable_set( DEVICESID, "DisplayStatus", resp.reason or "control failed", dev )
        else
            updateDeviceStatus( dev ) -- force display update, may happen again
            forceUpdate( dev )
            return true
        end
    end
    return false
end

local function sendModeAndSetpoints( dev )
    -- CT firmware requires that mode change is accompanied by both heating and 
    -- cooling setpoints, and that the setpoints honor the delta. Make it so.
    local dk = tostring(dev)
    local mode = luup.variable_get( OPMODE_SID, "ModeTarget", dev )
    local heatSP = getVarNumeric( "CurrentSetpoint", devData[dk].sysinfo.minHeatTemp, dev, SETPOINT_HEAT_SID )
    local coolSP = getVarNumeric( "CurrentSetpoint", devData[dk].sysinfo.maxCoolTemp, dev, SETPOINT_COOL_SID )
    local cfUnits = luup.variable_get( DEVICESID, "ConfiguredUnits", dev ) or "F"
    local xmap = { [MODE_OFF]=0, [MODE_AUTO]=3, [MODE_HEAT]=1, [MODE_COOL]=2 }
    local body = string.format("mode=%s&heattemp=%.1f&cooltemp=%.1f", xmap[mode] or 0, heatSP, coolSP)
    return doControl( body, dev )
end

-- Action for SetModeTarget -- change current operating mode
function actionSetModeTarget( dev, newMode )
    D("actionSetModeTarget(%1,%2)", dev, newMode)
    local xmap = { [MODE_OFF]=0, [MODE_AUTO]=3, [MODE_HEAT]=1, [MODE_COOL]=2 }
    if xmap[tostring(newMode)] == nil then
        L({level=1,msg="Unrecognized target mode requested for %1 (%2): %3"}, luup.devices[dev].description, dev, newMode)
        return false
    elseif not devData[tostring(dev)].sysinfo.hasModes[newMode] then
        L({level=2,msg="Unsupported mode requested for %1 (%2): %3"}, luup.devices[dev].description, dev, newMode)
        return false
    else
        luup.variable_set( OPMODE_SID, "ModeTarget", newMode, dev )
        return sendModeAndSetpoints( dev )
    end
end

-- Set fan operating mode (ignored)
function actionSetFanMode( dev, newMode )
    D("actionSetFanMode(%1,%2)", dev, newMode)
    local xmap = { [FANMODE_AUTO]=0, [FANMODE_ON]=1 }
    if xmap[tostring(newMode)] ~= nil then
        luup.variable_set( FANMODE_SID, "Mode", newMode, dev )
        return doControl( "fan=" .. ( xmap[newMode] or 0 ), dev )
    end
    return false
end

-- Action to change (TemperatureSetpoint1) setpoint.
function actionSetCurrentSetpoint( dev, newSP, app )
    D("actionSetCurrentSetpoint(%1,%2,%3)", dev, newSP, app)
    local dk = tostring(dev)
    local cfUnits = luup.variable_get( DEVICESID, "ConfiguredUnits", dev ) or "F"

    -- Clean up setpoint and convert to units of the thermostat.
    local temp,unit = string.match( tostring(newSP), "(%d+)(.?)" )
    if temp == nil then temp,unit = string.match( tostring(newSP), "(%d+%.%d*)(.?)" ) end
    if temp == nil then temp,unit = newSP, cfUnits end
    if unit == nil then unit = cfUnits end
    temp = convertTemp( temp, unit, cfUnits )
    local step = 1
    if cfUnits == "F" then
        temp = math.floor( temp + 0.5 ) -- whole degrees for F
    else
        temp = math.floor( temp * 2 ) / 2 -- half degrees for C
        step = 0.5
    end

    local currHeatSP = getVarNumeric( "CurrentSetpoint", devData[dk].sysinfo.minHeatTemp, dev, SETPOINT_HEAT_SID )
    local currCoolSP = getVarNumeric( "CurrentSetpoint", devData[dk].sysinfo.maxCoolTemp, dev, SETPOINT_COOL_SID )

    if app == "Cooling" then
        if ( temp - currHeatSP ) < devData[dk].sysinfo.delta then
            currHeatSP = temp - devData[dk].sysinfo.delta
            luup.variable_set( SETPOINT_HEAT_SID, "CurrentSetpoint", currHeatSP, dev )
        end
        luup.variable_set( SETPOINT_COOL_SID, "CurrentSetpoint", temp, dev )
    elseif app == "Heating" then
        if ( currCoolSP - temp ) < devData[dk].sysinfo.delta then
            currCoolSP = temp + devData[dk].sysinfo.delta
            luup.variable_set( SETPOINT_COOL_SID, "CurrentSetpoint", currCoolSP, dev )
        end
        luup.variable_set( SETPOINT_HEAT_SID, "CurrentSetpoint", temp, dev )
    elseif app == "DualHeatingCooling" then
        currHeatSP = temp - math.floor( devData[dk].sysinfo.delta / 2 )
        currCoolSP = currHeatSP + devData[dk].sysinfo.delta
        luup.variable_set( SETPOINT_COOL_SID, "CurrentSetpoint", currCoolSP, dev )
        luup.variable_set( SETPOINT_HEAT_SID, "CurrentSetpoint", currHeatSP, dev )
    end
    return sendModeAndSetpoints( dev )
end

-- Action to change energy mode (not implemented).
function actionSetEnergyModeTarget( dev, newMode )
    -- Store the target, but don't change status, because nothing changes, and signal failure.
    luup.variable_set( OPMODE_SID, "EnergyModeTarget", newMode, dev )
    return false
end

function actionSetHomeAway( dev, homeAway )
    if tostring(homeAway) == "0" or string.lower(homeAway) == "home" then
        homeAway = 0
    elseif tostring(homeAway) == "1" or string.lower(homeAway) == "away" then
        homeAway = 1
    else
        return false
    end
    return doControl( "away="..homeAway, dev )
end

function actionRunDiscovery( dev )
    launchDiscovery( dev )
end

function actionDiscoverMAC( dev, mac )
    local newMAC = (mac or ""):gsub("[%s:-]+", ""):upper()
    if newMAC:match("^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then
        discoveryByMAC( newMAC, dev )
    else
        gatewayStatus( "Invalid MAC address" )
        L("Discovery by MAC action failed, invalid MAC address: %1", mac)
    end
end

function actionDiscoverIP( dev, ipaddr )
    local newIP = (ipaddr or ""):gsub(" ", "")
    if newIP:match("^(%d+)%.(%d+)%.(%d+)%.(%d+):?") then -- loose, intentional
        discoveryByIP( newIP, dev )
    else
        gatewayStatus( "Invalid IP address" )
        L("Discovery by IP action failed, invalid IP address: %1", ipaddr)
    end
end

function actionSetDebug( dev, enabled )
    D("actionSetDebug(%1,%2)", dev, enabled)
    if enabled == 1 or enabled == "1" or enabled == true or enabled == "true" then
        debugMode = true
        D("actionSetDebug() debug logging enabled")
    end
end

local function plugin_checkVersion(dev)
    assert(dev ~= nil)
    D("checkVersion() branch %1 major %2 minor %3, string %4, openLuup %5", luup.version_branch, luup.version_major, luup.version_minor, luup.version, isOpenLuup)
    if isOpenLuup then return debugMode end
    if ( luup.version_branch == 1 and luup.version_major >= 7 ) then
        local v = luup.variable_get( MYSID, "UI7Check", dev )
        if v == nil then luup.variable_set( MYSID, "UI7Check", "true", dev ) end
        return true
    end
    return false
end

-- Do one-time initialization for a gateway
local function plugin_runOnce(dev)
    assert(dev ~= nil)
    assert(luup.devices[dev].device_num_parent == 0, "plugin_runOnce should only run on parent device")

    local rev = getVarNumeric("Version", 0, dev, MYSID)
    if (rev == 0) then
        -- Initialize for new installation
        D("runOnce() Performing first-time initialization!")
        initVar(MYSID, "DisplayStatus", "", dev)
        initVar(MYSID, "RefreshInterval", DEFAULT_REFRESH, dev)
        initVar(MYSID, "RunStartupDiscovery", 1, dev)
        initVar(MYSID, "Version", _CONFIGVERSION, dev)
        return true -- tell caller to keep going
    end

    -- No matter what happens above, if our versions don't match, force that here/now.
    if (rev ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
    end
    return true -- indicate to caller we should keep going
end

-- Start-up initialization for plug-in.
function plugin_init(dev)
    D("plugin_init(%1)", dev)
    L("starting version %1 for device %2 gateway", _PLUGIN_VERSION, dev )

    -- Up front inits
    pluginDevice = dev
    runStamp = {}
    runStamp[dev] = os.time()
    devData = {}
    devData[tostring(dev)] = {}
    math.randomseed( os.time() )
    
    if getVarNumeric( "DebugMode", 0, dev, MYSID ) ~= 0 then
        debugMode = true
    end

    -- Check for ALTUI and OpenLuup
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" then
            D("init() detected ALTUI")
            isALTUI = true
            local rc,rs,jj,ra = luup.call_action ("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=MYTYPE,
                    newScriptFile="J_VenstarColorTouchInterface1_ALTUI.js",
                    newDeviceDrawFunc="VenstarColorTouchInterface1_ALTUI.DeviceDraw"
                }, k )
            D("plugin_init() ALTUI's RegisterPlugin action for %5 returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra,MYTYPE)
            local rc,rs,jj,ra = luup.call_action ("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=DEVICETYPE,
                    newScriptFile="J_VenstarColorTouchThermostat1_ALTUI.js",
                    newDeviceDrawFunc="VenstarColorTouchThermostat1_ALTUI.DeviceDraw"
                }, k )
            D("plugin_init() ALTUI's RegisterPlugin action for %5 returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra,DEVICETYPE)
        elseif v.device_type == "openLuup" then
            D("init() detected openLuup")
            isOpenLuup = true
        end
    end

    -- Make sure we're in the right environment
    if not plugin_checkVersion(dev) then
        L("This plugin does not run on this firmware!")
        luup.variable_set( MYSID, "Failure", "1", dev )
        luup.set_failure( 1, dev )
        return false, "Unsupported system firmware", _PLUGIN_NAME
    end

    -- See if we need any one-time inits
    plugin_runOnce(dev)

    -- Other inits
    gatewayStatus( "" )

    -- Start up each of our children
    local children = inventoryChildren( dev )
    if #children == 0 and getVarNumeric( "RunStartupDiscovery", 1, dev, MYSID ) ~= 0 then
        launchDiscovery( dev )
    end
    for _,cn in ipairs( children ) do
        L("Starting device %1 (%2)", cn, luup.devices[cn].description)
        luup.variable_set( DEVICESID, "Failure", 0, cn ) -- IUPG
        local ok, err = pcall( deviceStart, cn, dev )
        if not ok then
            luup.variable_set( DEVICESID, "Failure", 1, cn )
            L("Device %1 (%2) failed to start, %3", cn, luup.devices[cn].description, err)
            gatewayStatus( "Device(s) failed to start!" )
        end
    end

    -- Mark successful start (so far)
    L("Running!")
    luup.set_failure( 0, dev )
    return true, "OK", _PLUGIN_NAME
end

function plugin_getVersion()
    return _PLUGIN_VERSION, _PLUGIN_NAME, _CONFIGVERSION
end

local function issKeyVal( k, v, s )
    if s == nil then s = {} end
    s["key"] = tostring(k)
    s["value"] = tostring(v)
    return s
end

local function map( m, v, d )
    if m[v] == nil then return d end
    return m[v]
end

local function getDevice( dev, pdev, v )
    local dkjson = require("dkjson")
    if v == nil then v = luup.devices[dev] end
    local devinfo = {
          devNum=dev
        , ['type']=v.device_type
        , description=v.description or ""
        , room=v.room_num or 0
        , udn=v.udn or ""
        , id=v.id
        , ['device_json'] = luup.attr_get( "device_json", dev )
        , ['impl_file'] = luup.attr_get( "impl_file", dev )
        , ['device_file'] = luup.attr_get( "device_file", dev )
        , manufacturer = luup.attr_get( "manufacturer", dev ) or ""
        , model = luup.attr_get( "model", dev ) or ""
    }
    local rc,t,httpStatus = luup.inet.wget("http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json", 15)
    if httpStatus ~= 200 or rc ~= 0 then
        devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%d, http=%d', rc, httpStatus )
        return devinfo
    end
    local d = dkjson.decode(t)
    local key = "Device_Num_" .. dev
    if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
    devinfo.states = d or {}
    return devinfo
end

function plugin_requestHandler(lul_request, lul_parameters, lul_outputformat)
    D("plugin_requestHandler(%1,%2,%3)", lul_request, lul_parameters, lul_outputformat)
    local action = lul_parameters['action'] or lul_parameters['command'] or ""
    local deviceNum = tonumber( lul_parameters['device'], 10 ) or luup.device
    if action == "debug" then
        local err,msg,job,args = luup.call_action( MYSID, "SetDebug", { debug=1 }, deviceNum )
        return string.format("Device #%s result: %s, %s, %s, %s", tostring(deviceNum), tostring(err), tostring(msg), tostring(job), dump(args))
    end

    if action:sub( 1, 3 ) == "ISS" then
        -- ImperiHome ISS Standard System API, see http://dev.evertygo.com/api/iss#types
        local dkjson = require('dkjson')
        local path = lul_parameters['path'] or action:sub( 4 ) -- Work even if I'home user forgets &path=
        if path == "/system" then
            return dkjson.encode( { id="VenstarColorTouchInterface-" .. luup.pk_accesspoint, apiversion=1 } ), "application/json"
        elseif path == "/rooms" then
            local roomlist = { { id=0, name="No Room" } }
            for rn,rr in pairs( luup.rooms ) do
                table.insert( roomlist, { id=rn, name=rr } )
            end
            return dkjson.encode( { rooms=roomlist } ), "application/json"
        elseif path == "/devices" then
            local devices = {}
            for lnum,ldev in pairs( luup.devices ) do
                if ldev.device_type == DEVICETYPE then
                    local cfUnits = luup.variable_get( DEVICESID, "ConfiguredUnits", lnum )
                    local dk = tostring(lnum)
                    local issinfo = {}
                    table.insert( issinfo, issKeyVal( "curmode", map( { Off="Off",HeatOn="Heat",CoolOn="Cool",AutoChangeOver="Auto" }, luup.variable_get( OPMODE_SID, "ModeStatus", lnum ), "Off" ) ) )
                    table.insert( issinfo, issKeyVal( "curfanmode", map( { Auto="Auto",ContinuousOn="On",PeriodicOn="Periodic" }, luup.variable_get(FANMODE_SID, "Mode", lnum), "Auto" ) ) )
                    table.insert( issinfo, issKeyVal( "curtemp", luup.variable_get( TEMPSENS_SID, "CurrentTemperature", lnum ), { unit="°" .. cfUnits } ) )
                    table.insert( issinfo, issKeyVal( "cursetpoint", getCurrentSetpoint( lnum ) ) )
                    table.insert( issinfo, issKeyVal( "step", 1 ) )
                    table.insert( issinfo, issKeyVal( "minVal", devData[dk].sysinfo.minHeatTemp ) )
                    table.insert( issinfo, issKeyVal( "maxVal", devData[dk].sysinfo.maxCoolTemp ) )
                    table.insert( issinfo, issKeyVal( "availablemodes", "Off,Heat,Cool,Auto" ) )
                    table.insert( issinfo, issKeyVal( "availablefanmodes", "Auto,On" ) )
                    table.insert( issinfo, issKeyVal( "defaultIcon", "https://www.toggledbits.com/assets/venstar/colortouch_mode_auto.png" ) ) -- ???
                    local dev = { id=tostring(lnum),
                        name=ldev.description or ("#" .. lnum),
                        ["type"]="DevThermostat",
                        params=issinfo }
                    if ldev.room_num ~= nil and ldev.room_num ~= 0 then dev.room = tostring(ldev.room_num) end
                    table.insert( devices, dev )
                end
            end
            return dkjson.encode( { devices=devices } ), "application/json"
        else
            local dev, act, p = string.match( path, "/devices/([^/]+)/action/([^/]+)/*(.*)$" )
            dev = tonumber( dev, 10 )
            if dev ~= nil and act ~= nil then
                act = string.upper( act )
                D("plugin_requestHandler() handling action path %1, dev %2, action %3, param %4", path, dev, act, p )
                if act == "SETMODE" then
                    local newMode = map( { OFF="Off",HEAT="HeatOn",COOL="CoolOn",AUTO="AutoChangeOver" }, string.upper( p or "" ) )
                    actionSetModeTarget( dev, newMode )
                elseif act == "SETFANMODE" then
                    local newMode = map( { AUTO="Auto", ON="ContinuousOn" }, string.upper( p or "" ) )
                    actionSetFanMode( dev, newMode )
                elseif act == "SETSETPOINT" then
                    local temp = tonumber( p, 10 )
                    if temp ~= nil then
                        actionSetCurrentSetpoint( dev, temp, "DualHeatingCooling" )
                    end
                else
                    D("plugin_requestHandler(): ISS action %1 not handled, ignored", act)
                end
            else
                D("plugin_requestHandler() malformed action request %1", path)
            end
            return "{}", "application/json"
        end
    end

    if action == "status" then
        local dkjson = require("dkjson")
        if dkjson == nil then return "Missing dkjson library", "text/plain" end
        local st = {
            name=_PLUGIN_NAME,
            version=_PLUGIN_VERSION,
            configversion=_CONFIGVERSION,
            author="Patrick H. Rigney (rigpapa)",
            url=_PLUGIN_URL,
            ['type']=MYTYPE,
            responder=luup.device,
            timestamp=os.time(),
            system = {
                version=luup.version,
                isOpenLuup=isOpenLuup,
                isALTUI=isALTUI,
                units=luup.attr_get( "TemperatureFormat", 0 ),
            },
            devices={}
        }
        for k,v in pairs( luup.devices ) do
            if v.device_type == MYTYPE then
                local gwinfo = getDevice( k, luup.device, v ) or {}
                local children = inventoryChildren( k )
                gwinfo.children = {}
                for _,cn in ipairs( children ) do
                    table.insert( gwinfo.children, getDevice( cn, luup.device ) )
                end
                table.insert( st.devices, gwinfo )
            end
        end
        return dkjson.encode( st ), "application/json"
    end

    return "<html><head><title>" .. _PLUGIN_NAME .. " Request Handler"
        .. "</title></head><body bgcolor='white'>Request format: <tt>http://" .. (luup.attr_get( "ip", 0 ) or "...")
        .. "/port_3480/data_request?id=lr_" .. lul_request
        .. "&action=</tt><p>Actions: status, debug, ISS"
        .. "<p>Imperihome ISS URL: <tt>...&action=ISS&path=</tt><p>Documentation: <a href='"
        .. _PLUGIN_URL .. "' target='_blank'>" .. _PLUGIN_URL .. "</a></body></html>"
        , "text/html"
end