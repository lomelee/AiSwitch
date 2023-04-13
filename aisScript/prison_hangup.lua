-- 罪犯挂机
local api = freeswitch.API()
local cJson = freeswitch.JSON()
local aisWebUrl = freeswitch.getGlobalVariable("web_config_url")
-- 获取会话ID参数
local fUuid = argv[1]
-- 获取罪犯分机号
local prisonExtenNo = argv[2]

freeswitch.consoleLog("INFO", "罪犯分机：" .. prisonExtenNo .. " is hangup\n")
-- 定义通话会议头
local confNameHeader = "Prison-Conf-"
-- 构造通话会议名称
local confName = confNameHeader .. prisonExtenNo

-- 获取外线通道UUID
local function getDestChannelUuid()
    local hashKey = "select/" .. confName .. "/dest/"
    return api:executeString("hash " .. hashKey) or ""
end

-- 获取民警通道UUID
local function getPoliceChannelUuid()
    local hashKey = "select/" .. fUuid .. "/policeId/"
    return api:executeString("hash " .. hashKey) or ""
end

-- 系统睡眠时间
local function Sleep(n)
    os.execute("sleep " .. n)
end

local destUuid = getDestChannelUuid()
local policeUuid = getDestChannelUuid()

local function clearSession()
    -- 删除会议指定的活动时间
    local hashKey = "delete/" .. confName .. "/actiontime/"
    api:executeString("hash " .. hashKey)

    -- 删除fuuid指定的录音时间（释放内存）
    hashKey = "delete/" .. fUuid .. "/recordTime/"
    api:executeString("hash " .. hashKey)

    -- 删除fuuid 对应的民警编号（释放内存）
    hashKey = "delete/" .. fUuid .. "/policeId/"
    api:executeString("hash " .. hashKey)

    if policeUuid ~= "" then
        api:executeString("uuid_kill " .. policeUuid)
        freeswitch.consoleLog("INFO", "拆管理员端!\n")
    end

    -- 结束会议，挂断所有成员
    api:executeString("conference " .. confName .. " hup all")
    if destUuid ~= "" then
        api:executeString("uuid_kill " .. destUuid)
        freeswitch.consoleLog("INFO", "拆外线端!\n")
    end
    Sleep(1)
end

-- 执行清空会话
clearSession()

local checkDest = api:executeString("uuid_exists " .. destUuid)
local checkPolice = api:executeString("uuid_exists " .. policeUuid)
if "true" == checkDest or "true" == checkPolice then
    freeswitch.consoleLog("INFO", "再次执行拆线!\n")
    clearSession();
end

-- 执行通话完成的通知，此通知后将回调通知通话记录
local function sendPrisonConfFinishMsg(prisonChanId, relativeChanId, policeChanId, fUuid)
    -- 构造请求参数
    local msgObj = {}
    msgObj.prisonChanId = prisonChanId
    msgObj.relativeChanId = relativeChanId
    msgObj.policeChanId = policeChanId
    msgObj.fUuid = fUuid

    -- 构造请求参数
    local jsonParams = cJson:encode(msgObj)
    -- 构造请求地址
    local APIUrl = aisWebUrl .. "/prison/conf/finish"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " content-type application/json post '" .. jsonParams .. "'")
    -- 打印返回值
    freeswitch.consoleLog("INFO", "sendPrisonConfFinishMsg resultData : " .. resultData .. "\n")
    -- 解析json字符串
    local resultObj = cJson:decode(resultData)

    if resultObj == nil or resultObj == "" then
        freeswitch.consoleLog("WARNING", "sendPrisonConfFinishMsg *** 调用失败 ***\n")
    end

    if resultObj.code ~= "200" then
        freeswitch.consoleLog("WARNING",
            "sendPrisonConfFinishMsg *** 返回失败[msg]： " .. resultObj.msg .. " ***\n")
    end
end

-- 发送结束会议和通话的消息
sendPrisonConfFinishMsg(fUuid, destUuid, policeUuid, fUuid);
