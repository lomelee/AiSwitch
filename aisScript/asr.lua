local api = freeswitch.API()
local confName = argv[1] or ""
local preName = argv[2] or ""
local destNum = argv[3] or ""

session:answer()
-- 如果是外线接通，记录开始通话时间
if "dest" == preName then
    -- 记录通话开始时间
    local nowTime = os.time()

    -- 获取指定会议的最大通话时长
    local hashKey = "select/" .. confName .. "/maxdur"
    local maxdur = api:executeString("hash " .. hashKey) or 0
    local maxdurVal = tonumber(maxdur) or 0
    freeswitch.consoleLog("INFO", "confName : " .. confName .. ", maxdur : " .. maxdur .. "\n")

    -- 如果亲属端接听通话，那么计算最大通话时长
    if maxdurVal > 0 then
        local endTime = nowTime + maxdurVal * 60
        hashKey = "insert/" .. confName .. "/endtime/" .. endTime
        api:executeString("hash " .. hashKey)
        freeswitch.consoleLog("INFO", "confName : " .. confName .. ", endTime : " .. endTime .. "\n")
    end

    -- 设置会议通话开始时间
    hashKey = "insert/" .. confName .. "/begintime/" .. nowTime
    api:executeString("hash " .. hashKey)
    freeswitch.consoleLog("INFO", "confName : " .. confName .. ", beginTime : " .. nowTime .. "\n")
    -- 停止会议中所有的播放
    api:executeString("conference " .. confName .. " stop all")
    -- 打印信息
    freeswitch.consoleLog("INFO", "dest confName : " .. confName .. ", beginTime : " .. nowTime .. ", destNum: " ..
        destNum .. "\n")
end

-- 设置录音文件名称
local rfName = confName .. "-" .. destNum
-- 执行录音（单腿）
session:execute("lua", "record.lua " .. rfName .. " " .. preName)

-- 如果配置的ASR为 on 那么使用unimrcp 连接 ASR 引擎，发起翻译
local asrController = session:getVariable("asr_controller") or "off"
if asrController == "on" then
    session:setVariable("asr_engine", "unimrcp:AisMRCPV2")
    session:setVariable("fire_asr_events", "true")
    session:execute("detect_speech",
        "unimrcp:AisMRCPV2 {start-input-timers=false,no-input-timeout=10000,recognition-timeout=60000,start-recognize=true,define-grammar=false}hello hello")
end
