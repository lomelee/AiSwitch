local cJson = freeswitch.JSON()
local api = freeswitch.API()
local ctrlSysRingBack = freeswitch.getGlobalVariable("CtrlSysRingBack") or "on"
-- 定义呼出到网关的等待时间
local callGwWaitTime = 20

-- 系统睡眠时间
local function Sleep(n)
    os.execute("sleep " .. n)
end

-- 获取系统中的会议列表
local function getSysConfList()
    local arrConfs = {}
    local msg, err = api:executeString("conference list ")
    for confName in string.gmatch(msg, 'Prison%-Conf%-%d+') do
        table.insert(arrConfs, confName)
    end
    return arrConfs
end

-- 获取当前会议的成员数量
local function getConfMemberCount(confName)
    local count, err = api:executeString("conference " .. confName .. " count")
    -- 如果没有获取到成员信息
    if count == nil then
        count = 0
    end
    freeswitch.consoleLog("INFO", confName .. " count :" .. count .. "---\n")
    return count
end

-- 获取当前活动的时间
local function getConfActionTime(confName)
    local hashKey = "select/" .. confName .. "/actiontime"
    return tonumber(api:executeString("hash " .. hashKey)) or 0
end

-- 获取当前会议的开始时间
local function getConfBeginTime(confName)
    local hashKey = "select/" .. confName .. "/begintime"
    return tonumber(api:executeString("hash " .. hashKey)) or 0
end

-- 获取当前会议的结束时间
local function getConfEndTime(confName)
    local hashKey = "select/" .. confName .. "/endtime"
    return tonumber(api:executeString("hash " .. hashKey)) or 0
end

-- 获取会议目标号码的UUID
local function getConfDestUuId(confName)
    local hashKey = "select/" .. confName .. "/dest/"
    local confUuid = api:executeString("hash " .. hashKey) or ""
    return confUuid
end

local loopNum = 0
local confList = {}

while true do
    Sleep(5)

    loopNum = loopNum + 1
    if loopNum == 60000 then
        loopNum = 0
    end
    -- 找到需要定时处理的会议列表
    confList = getSysConfList()
    for index = 1, #confList do
        local confName = confList[index]
        -- 获取指定会议的成员数量
        local memCount = getConfMemberCount(confName)
        -- 获取会议其他参数
        local actionTime = getConfActionTime(confName)
        local beginTime = getConfBeginTime(confName)
        local endTime = getConfEndTime(confName)
        local destUuid = getConfDestUuId(confName)
        -- 获取当前时间
        local nowTime = os.time()
        -- 会议活动时间大于0
        if actionTime > 0 then
            -- 查找到外线对应的通道信息
            local channelsJson = api:executeString("show channels like " .. destUuid .. " as json")
            local chansObj = cJson:decode(channelsJson)
            -- 没有解析到对应UUID的外线通道
            if nil ~= chansObj then
                if 0 ~= chansObj.row_count then
                    local callstate = chansObj.rows[1].callstate
                    freeswitch.consoleLog("INFO",
                        confName .. " 外线状态  callstate ------ " .. callstate .. "-----\n")
                    -- 如果外线还为
                    if ctrlSysRingBack == "on" and callstate == "RINGING" or callstate == "EARLY" and beginTime == 0 then
                        -- 向会议中播放回铃音（可以直接播放语音文件）
                        -- api:executeString("conference " .. confName .. " play custom/thanks.wav")
                        api:executeString("conference " .. confName .. " play tone_stream://%(2000,4000,440,480)")

                    end
                else
                    -- 此处的判断有几种情况：
                    if beginTime > 0 then
                        -- 1、外线接通后挂断，那么结束通话
                        freeswitch.consoleLog("WARNING", "loop check " .. confName ..
                            ", relative channels is None, may be Has Hangup, Hangup All \n")
                        api:executeString("conference " .. confName .. " hup all")
                    elseif (nowTime - actionTime) > callGwWaitTime then
                        -- 1、外线刚刚加入通道，做等待处理（等待 maxWaitTime 已经足够），避免外线还没有准备好接入网关就直接挂断了
                        -- 2、外线还未接听，就已经挂断（最多等待 maxWaitTime 时间后挂断）
                        freeswitch.consoleLog("WARNING", "loop check " .. confName ..
                            ", relative channels is None, No Answer, Hangup All \n")
                        api:executeString("conference " .. confName .. " hup all")
                    end
                end
            end
        end

        -- 最大通话时间存在，且剩余时间小于 60s 
        if beginTime > 0 and endTime > 0 and endTime - nowTime <= 60 then
            -- 每两次循环（10秒）提醒一次 “时间快到了”
            if loopNum % 2 == 0 then
                -- 计算剩下的通话时间
                local balanceTime = endTime - nowTime;
                if balanceTime > 0 then
                    freeswitch.consoleLog("INFO", confName .. ", balanceTime = " .. balanceTime .. " 嘟~ \n")
                    api:executeString("conference " .. confName .. " play tone_stream://%(275,10,600);%(275,100,300)")
                else
                    freeswitch.consoleLog("WARNING", confName .. ", balanceTime =  " .. balanceTime ..
                        " 超过最大通话时间挂机! \n")
                    api:executeString("conference " .. confName .. " hup all")
                end
            end
        end
    end
end
