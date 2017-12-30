-- OSD Show External Info (info not related to mpv player or media played)
--
-- Shows OSD various external info (modality) like weather forecast, new emails,
-- traffic conditions, currency exchange rates, clock, etc.
--
-- Modalities currently (dec'17) supported (stay tuned as more modalities will be added later):
--
-- OSD-CLOCK - shows clock periodicaly - configurable options:
--   interval ... how often to show OSD clock, either seconds or human friendly format like '1h 33m 5s' supported
--   format   ... date format string
--   duration ... how long [in seconds] OSD msg stays, fractional values supported
--   key      ... to bind showing OSD clock on request (false for no binding)
--
-- To customize configuration place osd-clock.conf into ~/.config/mpv/lua-settings/ and edit
--
-- OSD-EMAIL - shows new email count periodically - configurable options:
--   url      ... url to connect to imap/pop server
--   userpass ... authentication in login:password format
--   request  ... request to send to get new email count
--   response ... response from email server to parse to get raw new email count
--   cntofs   ... offset compensation of unread email count (will be subtracted before evaluatimg, should be 0)
--   showat   ... at what time to show OSD email status, seconds or human friendly format like '33m 5s' supported
--   interval ... how often to show OSD email status, either seconds or human friendly format like '1h 33m 5s' supported
--   osdpos   ... msg shown if count os new emails is positive (you have xx new emails)
--   osdneg   ... msg shown if count of new emails is negative (warning: fix offset cfg.cntofs)
--   osdzero  ... msg shown if count of new emails is equal zero (no new emails)
--   osderr   ... error message shown in case of any curl error
--   duration ... how long [in seconds] OSD msg stays, fractional values supported
--   key      ... to bind showing OSD email count on request (false for no binding)
--
--   https://debian-administration.org/article/726/Performing_IMAP_queries_via_curl
--   http://www.faqs.org/rfcs/rfc2060.html
--
--   curl --user "login:password" --url "imap://imap.domain" --request "STATUS INBOX (UNSEEN)"
--   * STATUS "INBOX" (UNSEEN 122)
--
--   curl --user "login:password" --url "imap://imap.domain/INBOX" --request 'SEARCH NEW FROM "vip@company.com"'
--   * SEARCH
--   * SEARCH 304 318 342 360 372
--
-- To customize configuration place osd-email.conf into ~/.config/mpv/lua-settings/ and edit
--
--
-- Place script into ~/.config/mpv/scripts/ for autoload
--
-- GitHub: https://github.com/blue-sky-r/mpv/tree/master/scripts

local options = require("mp.options")
local utils   = require("mp.utils")

-- defaults per modality
local cfg = {

    ['osd-clock'] = {
	    interval = '15m',
	    format   = "%H:%M",
	    duration = 2.5,
	    key      = 'h'
    },

    ['osd-email'] = {
        url      = 'imap://imap.domain',
        userpass = 'login:pass',
        request  = 'STATUS INBOX (UNSEEN)',
        response = '* STATUS "INBOX" %(UNSEEN (%d+)%)',
        cntofs   = 0,
        showat   = '58m',
        interval = '1h',
        osdpos   = 'You have %d new email(s)',
        osdneg   = 'WRN: fix offset cfg.cntofs:%d',
        osdzero  = 'No New emails',
        osderr   = 'ERR: %s',
        duration = 3.5,
        key      = 'e'
    },

    ['osd-weather'] = {
        showat   = '55',
        interval = '1h',
        format   = 'Today: %d Tomorrow: %s',
        duration = 5.5,
        key      = 'w'
    }
}

-- human readable time format to seconds: 15m 3s -> 903
local function htime2sec(hstr)
	local s = tonumber(hstr)
	-- only number withoout units
	if s then return s end
	-- human units h,m,s to seconds
	local hu = {h=60*60, m=60, s=1}
	s = 0
	for unit,mult in pairs(hu) do
		local _,_,num = string.find(hstr, "(%d+)"..unit)
		if num then
			s = s + tonumber(num)*mult
		end
	end
	return s
end

-- calc aligned timeout in sec
local function aligned_timeout(align)
    -- special case align=0 => align=60*60 [1h]
    -- if align == 0 then align = 60*60 end
	local time = os.time()
	local atout = align * math.ceil(time / align) - time
	return atout
end

-- calc delay till next ts
local function timeout_till(ts)
    -- current min/sec in seconds
    local curminsec = os.time() % 3600
    -- calc delay
    local delay = ts - curminsec
    -- next hour if delay is negative
    if delay < 0 then delay = 3600 + delay end
    return delay
end

-- string v is empty
local function empty(v)
	return not v or v == '' or string.find(v,"^%s*$")
end

-- execute shell cmd and return stdout and stderr
local function exec(cmd)
	-- return if there is nothing to execute
	if empty(cmd) then return end
	-- get stdout and stderr combined
	local stdcom = io.popen(cmd..' 2>&1'):read('*all')
	-- log
	mp.msg.info("exec ["..cmd.."]")
	if stdcom then
        mp.msg.verbose(stdcom)
    end
   	return stdcom
end

-- perform curl request and return response
local function curl(url, userpass, request)
    -- connection timeout
    local timeout = 3
	local cmd = 'curl -sS --connect-timeout '..timeout..' --url "'..url..'"'
	if userpass then cmd = cmd..' --user "'..userpass..'"' end
	if request  then cmd = cmd.." --request '"..request.."'" end
	local rs = exec(cmd)
	return rs
end

-- get email count via curl and return tuple (count, response)
local function email_cnt(cfg)
    local rs = curl(cfg.url, cfg.userpass, cfg.request)
    local cnt = tonumber(rs:match(cfg.response))
    return cnt, rs
end

-- formatted mail status msg or error/warning
local function osd_email_msg(cfg)
    local cnt, rs = email_cnt(cfg)
    if cnt then
        cnt = cnt - cfg.cntofs
        if cnt > 0 then
            -- msg for positive count(new)
            return string.format(cfg.osdpos, cnt)
        end
        if cnt < 0 then
            -- msg for negative count(new) [should be warning to update cfg]
            return string.format(cfg.osdneg, cfg.cntofs)
        end
        -- msg for no new emails
        return string.format(cfg.osdzero, cfg.cntofs)
    end
    -- error msg
    return string.format(cfg.osderr, rs)
end

-- OSD - show email status
function osd_email()
    local msg = osd_email_msg(cfg['osd-email'])
    if msg then
    	mp.osd_message(msg, cfg['osd-email'].duration)
    end
end

-- OSD - show clock
function osd_clock()
	local s = os.date(cfg['osd-clock'].format)
	mp.osd_message(s, cfg['osd-clock'].duration)
end

-- init timer, startup delay, key binding for specific modality from cfg
local function setup_modality(modality)

    -- modality section
    local conf = cfg[modality]

    -- read lua-settings/key.conf
    options.read_options(conf, modality)

    -- log active config
    mp.msg.verbose(modality..'.cfg = '..utils.to_string(conf))

    -- non empty interval enables osd clock
    if conf.interval then

        -- function name from modality
        local fname = modality:gsub('-', '_')
        -- call this function in global namespace for OSD
        local osd = _G[fname]

        -- osd timer
        local osd_timer = mp.add_periodic_timer( htime2sec(conf.interval), osd)
        osd_timer:stop()

        -- the 1st delay to start periodic timer
        local delay
        -- optional show_at
        if conf.showat then
            -- delay start till next showat
            delay = timeout_till( htime2sec(conf.showat) )
        else
            -- start osd timer exactly at interval boundary
            delay = aligned_timeout( htime2sec(conf.interval) )
        end

        -- delayed start
        mp.add_timeout(delay,
            function()
                osd_timer:resume()
                osd()
            end
        )

        -- log startup delay for osd timer
        mp.msg.verbose(modality..'.interval:'..conf.interval..' calc.delay:'..delay)

        -- optional key binding
        if conf.key then
            mp.add_key_binding(conf.key, fname, osd)
            -- log binding
            mp.msg.verbose(modality..".key:'"..conf.key.."' bound to '"..fname.."'")
        end
    end
end

-- main --
setup_modality('osd-clock')
setup_modality('osd-email')