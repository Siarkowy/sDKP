--------------------------------------------------------------------------------
-- sDKP (c) 2011 by Siarkowy
-- Released under the terms of GNU GPL v3 license.
--------------------------------------------------------------------------------

local sDKP = sDKP

local abs = abs
local assert = assert
local format = format
local match = string.match
local mod = mod
local pairs = pairs
local select = select
local sort = sort
local strjoin = strjoin
local strsplit = strsplit
local time = time
local tinsert = tinsert
local tonumber = tonumber
local tostring = tostring
local tremove = tremove
local unpack = unpack
local GetItemInfo = GetItemInfo
local GetTime = GetTime

local LOG_DATEFORMAT    = "%y-%m-%d %X"
local LOG_DELIMETER     = "\a"

-- Log entry types
local LOG_UNKNOWN       = -1
local LOG_PLAYER_LOOT   = 0
local LOG_DKP_MODIFY    = 1
local LOG_DKP_RAID      = 2
local LOG_DKP_CLASS     = 3
local LOG_PARTY_KILL    = 4
local LOG_IRONMAN_START = 5
local LOG_IRONMAN_CANCEL = 6
local LOG_IRONMAN_AWARD = 7

-- Helper functions ------------------------------------------------------------

local function tostringall(...)
    if select('#', ...) > 1 then
        return tostring(select(1, ...)), tostringall(select(2, ...));
    else
        return tostring(select(1, ...));
    end
end

local function serialize(...)
    return strjoin(LOG_DELIMETER, tostringall(...))
end

local function unserialize(data)
    return strsplit(LOG_DELIMETER, data)
end

-- Save to Util
sDKP.tostringall = tostringall
sDKP.LogSerialize = serialize
sDKP.LogUnserialize = unserialize

-- Log -> String handling ------------------------------------------------------

--- Log entry formatting handlers
-- Contains type<->func pairs.
-- @param type (number) Entry type.
-- @param func (function) Formatting function which is passed unpacked data from log.
sDKP.LogToStringHandlers = {
    [LOG_PLAYER_LOOT] = function(player, item, count) -- 0
        local _, link = GetItemInfo(item)
        count = tonumber(count) or 1
        return format("%s looted %s%s.", sDKP.ClassColoredPlayerName(player), link or "<unknown item>", count > 1 and format("x%d", count) or "")
    end,

    [LOG_DKP_MODIFY] = function(player, points, reason) -- 1
        points = tonumber(points) or 0
        if tonumber(reason) then
            _, reason = GetItemInfo(reason)
        end
        return format("%s %+d DKP%s.", sDKP.ClassColoredPlayerName(player), points, reason and format(": %s", reason) or "")
    end,

    [LOG_DKP_RAID] = function(count, points, reason) -- 2
        count = tonumber(count) or 0
        points = tonumber(points) or 0
        if tonumber(reason) then
            _, reason = GetItemInfo(reason)
        end
        return format("Raid (%d |4player:players;) %+d DKP%s.", count, points, reason and format(": %s", reason) or "")
    end,

    [LOG_DKP_CLASS] = function(class, count, points, reason) -- 3
        count = tonumber(count) or 0
        points = tonumber(points) or 0
        if tonumber(reason) then
            _, reason = GetItemInfo(reason)
        end
        return format("%ss (%d |4player:players;) %+d DKP%s.", gsub(class, "^(.)", string.upper), count, points, reason and format(": %s", reason) or "")
    end,

    [LOG_PARTY_KILL] = function(mob) -- 4
        return format("%s has been slain.", mob)
    end,

    [LOG_IRONMAN_START] = function(count) -- 5
        count = tonumber(count) or 0
        return format("Ironman started for %d |4player:players;.", count)
    end,

    [LOG_IRONMAN_CANCEL] = function() -- 6
        return "Ironman canceled."
    end,

    [LOG_IRONMAN_AWARD] = function(count, points) -- 7
        return format("Ironman awarded: %d |4player:players; %+d DKP.", count, points)
    end
}

local handlers = sDKP.LogToStringHandlers

function sDKP.LogToString(data)
    local type, a, b, c, d, e, f, g, h, i = unserialize(data)
    type = tonumber(type) or LOG_UNKNOWN
    return handlers[type](a, b, c, d, e, f, g, h, i)
end

-- Logging methods -------------------------------------------------------------

function sDKP:CheckLogPresence()
    if self.guild and not self.LogData[self.guild] then
        self.LogData[self.guild] = { }
    end
end

--- Logs data to current guild's log.
-- @param type (integer) Entry type integer, see LOG_* locals.
-- @param ... (tuple) Data list to serialize. Nils are ignored.
function sDKP:Log(type, ...)
    if not self.guild then return end

    local log = self.LogData[self.guild]
    local t = self.table()

    for i = 1, select("#", ...) do
        tinsert(t, (select(i, ...)))
    end

    local stamp = time() + mod(GetTime(), 1) -- calculate timestamp

    while log[stamp] do -- if already used
        stamp = stamp + 0.01
    end

    log[stamp] = serialize(type, unpack(t))
end

local result = { }
function sDKP:PrepareLog(startTime, endTime)
    startTime = startTime or time() - 86400 -- 1 day
    endTime = endTime or time()
    while (tremove(result)) do end
    for timestamp, data in pairs(self.LogData[self.guild]) do
        if timestamp >= startTime and timestamp <= endTime then
            tinsert(result, timestamp)
        end
    end
    sort(result)
    return result
end

-- Slash handlers --------------------------------------------------------------

function sDKP:LogDump()
    self:Print("Full log entry list:")
    local node = self.LogData[self.guild]
    local count = 0
    for _, timestamp in pairs(self:PrepareLog(0)) do
        self:Echo("|cff888888[%s]|r %s", date(LOG_DATEFORMAT, timestamp), self.LogToString(node[timestamp]))
        count = count + 1
    end
    self:Echo("Total of %d |4entry:entries;.", count)
end

function sDKP:LogRecent(param)
    local timestamp = self.ParamToTimestamp(param) or time() - 86400 -- 1 day
    self:Printf("Log entry list from %s:", date(LOG_DATEFORMAT, timestamp))
    local node = self.LogData[self.guild]
    local count = 0
    for _, timestamp in pairs(self:PrepareLog(timestamp)) do
        self:Echo("|cff888888[%s]|r %s", date(LOG_DATEFORMAT, timestamp), self.LogToString(node[timestamp]))
        count = count + 1
    end
    self:Echo("Total of %d |4entry:entries;.", count)
end

function sDKP:LogPurge(param)
    local timestamp = self.ParamToTimestamp(param) or time() - 345600 -- 4 weeks
    local node = self.LogData[self.guild]
    local count = 0
    for t, d in pairs(node) do
        if t < timestamp then
            node[t] = nil
            count = count + 1
        end
    end
    self:Printf("%d |4entry:entries; purged.", count)
end

function sDKP:LogSearch(param)
    local param, chan = self.ExtractChannel(param, "SELF")
    local node = self.LogData[self.guild]
    local count = 0
    for timestamp, entry in self.PairsByKeys(node) do
        for str in param:gmatch("[^|]+") do
            if entry:match(str) then
                self:Announce(chan, "|cff888888[%s]|r %s",
                    date(LOG_DATEFORMAT, timestamp), self.LogToString(entry))
                count = count + 1
            end
        end
    end
    self:Echo("Total of %d |4entry:entries;.", count)
end

sDKP.Slash.args.log = {
    type = "group",
    name = "Log",
    desc = "Operation log functions.",
    args = {
        dump = {
            name = "Dump",
            desc = "Prints all entries from log into chat frame.",
            type = "execute",
            func = "LogDump",
            order = 1
        },
        purge = {
            name = "Purge",
            desc = "Deletes log entries for current guild older than specified or at least 4 weeks old if no parameter given.",
            type = "execute",
            usage = "[<timestamp>]",
            func = "LogPurge",
            order = 2
        },
        recent = {
            name = "Recent",
            desc = "Prints log entries from last 1 day or newer than given timestamp.",
            type = "execute",
            usage = "[<timestamp>]",
            func = "LogRecent",
            order = 3
        },
        search = {
            name = "Search",
            desc = "Shows all entries matching given string(s).",
            type = "execute",
            usage = "<query>[||...] [@<channel>]",
            func = "LogSearch",
            order = 4
        },
    }
}
