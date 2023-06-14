local api = freeswitch.API()
-- 录音文件名称
local recordName = argv[1] or ""
-- 会议名称参数
local confName = argv[2]
-- 录音对应的UUID
local recordUuid = session:getVariable("fuuid") or api:executeString("create_uuid")
-- 录音文件保存路径 /usr/local/freeswitch/recordings
local baseDir = freeswitch.getGlobalVariable("recordings_dir") or "/usr/local/freeswitch/recordings"
-- 是否按照日期拆分目录
local isByDay = freeswitch.getGlobalVariable("recordings_dir_day") or "false"

-- 获取录音时间(首先查询Hash表中是否存在录音时长，这样做的好处是，时间未天的临界点时，录音出现在不同的文件夹)
local selKey = "select/" .. recordUuid .. "/recordTime/"
local recordTime = api:executeString("hash " .. selKey) or os.time()
recordTime = tonumber(recordTime)

-- 如果按照日期拆分目录
local strday = ""
if isByDay == "true" then
    strday = os.date("%Y/%m/%d", recordTime)
    strday = strday .. "/"
end

-- 录音文件时间戳
local timeFlag = os.date("%Y%m%d%H%M%S", recordTime)

-- 如果没有录音名称的参数
if recordName == "" then
    local newRfName = timeFlag .. "-confe-" .. recordUuid .. ".wav"
    recordName = newRfName
else
    local newRfName = timeFlag .. "-confe-" .. recordName .. ".wav"
    recordName = newRfName
end

-- 录音文件短路径
local recordShortPath =  strday .. recordName
-- 录音文件名用来写入 calls_list 表
-- session:setVariable("record_file_name", recordShortPath)
-- 设置多个通道同时存在该参数
session:execute("export", "record_file_name=" .. recordShortPath)
-- 设置会议参数
-- api:executeString("conference " .. confName .. " set record_file_name " .. recordShortPath)
freeswitch.consoleLog("INFO", "record_conference_name is " .. recordShortPath .. "\n")
-- 执行会议录音 API（可能会议还没有开始, 所以使用 set conference_auto_record 参数的形式）
-- local resultData = api:executeString("conference " .. confName .. " record " .. baseDir .. recordShortPath)
-- freeswitch.consoleLog("NOTICE", "record_conference_name is " .. resultData .. ", " .. recordShortPath .. " \n")
-- 设置自动录音的路径
session:execute("set", "conference_auto_record=" .. baseDir .. "/" .. recordShortPath)