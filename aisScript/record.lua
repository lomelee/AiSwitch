local api = freeswitch.API()
-- 录音文件名称
local recordName = argv[1] or ""
-- 设置录音文件名称（前缀为SUM表示综合录音）
local preName = argv[2] or "SUM"
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
    strday = os.date("%Y%m%d", recordTime)
    strday = strday .. "/"
end

-- 录音文件时间戳
local timeFlag = os.date("%Y%m%d%H%M%S", recordTime)

-- 如果没有录音名称的参数
if recordName == "" then
    -- 主叫号码  可能是内线， 也可能是外线
    local caller = session:getVariable("caller_id_number")
    -- 被叫号码
    local destnum = session:getVariable("dialed_extension")
    -- 修正获取的被叫号码
    if destnum == nil or destnum == "" then
        destnum = session:getVariable("destination_number")
    end
    local newRfName = timeFlag .. "-" .. preName .. "-" .. caller .. "-" .. destnum .. ".wav"
    recordName = newRfName
else
    local newRfName = timeFlag .. "-" .. preName .. "-" .. recordName .. ".wav"
    recordName = newRfName
end

-- 录音文件短路径
local recordShortPath = strday .. recordName

-- 如果不是综合录音，设置单腿录音参数
if preName ~= "SUM" then
    session:setVariable("RECORD_STEREO", "false")
    -- true : 只录“写”方向的录音。这里的方向是相对FreeSWITCH而言的，即FreeSWITCH发出声音。
    session:setVariable("RECORD_WRITE_ONLY", "false")
    -- true：只录“读”方向的录音，即FreeSWITCH“听”到的录音。
    session:setVariable("RECORD_READ_ONLY", "true")
    -- 录音文件名 用来写入 calls_list 表
    session:setVariable("record_leg_name", recordShortPath)
    -- 打印录音文件名
    freeswitch.consoleLog("INFO", "record_leg_name  is " .. recordShortPath .. "\n")
else
    -- 立体声录音(两个通道分别录音到不同的声道中)
    session:setVariable("RECORD_STEREO", "true")
    session:setVariable("RECORD_WRITE_ONLY", "false")
    session:setVariable("RECORD_READ_ONLY", "false")
    -- 录音文件名 用来写入 calls_list 表
    session:setVariable("record_file_name", recordShortPath)
    -- 打印录音文件名
    freeswitch.consoleLog("INFO", "record_file_name  is " .. recordShortPath .. "\n")
end

-- 执行录音（record_session 非阻塞录音，record 为阻塞录音命令或者APP）
session:execute("record_session", baseDir .. "/" .. recordShortPath)
