local api = freeswitch.API()
local cJson = freeswitch.JSON()
local domain = session:getVariable("domain_name")
local context = session:getVariable("user_context")
local fUuid = session:get_uuid()
local prisonExten = session:getVariable("caller_id_number")
-- 外呼字符串,多个网关可以用|分割, sofia/gateway/gw-jude/68|
local gatewayName = session:getVariable("Prison_Gateway_Name") or ""
local aisWebUrl = session:getVariable("web_config_url")
local apiUrl = session:getVariable("Prison_ApiUrl")
local prisonCode = session:getVariable("Prison_Code")
local prisonBusNo = ""
local policeExtenNo = ""
local prison_no_len_min = 3
local prison_no_len_max = 15
local prison_new_pwd_len = 6
-- 会议名称前缀
local confNameHeader = "Prison-Conf-"
-- 定义呼叫功能次数（初始化为0）
local callFutureTime = 0;

-- 定义罪犯信息
local prisonInfo = {}
-- 罪犯登录密码
prisonInfo.pwd = ""
-- 剩余拨打次数
prisonInfo.callTime = 0
-- 剩余话费余额
prisonInfo.surplustime = 0
-- 最大通话时长
prisonInfo.maxdur = 0
-- 是否开启倒计时
prisonInfo.isCountdown = false
-- 联系人列表
prisonInfo.relatives = {}

-- 获取格式化后的日期时间
local function getFormatDateTime()
    local sysTime = os.time()
    local fsMilliTime = api:getTime() / 1000
    -- 获取毫秒数
    local millisecond = string.format("%03d", (fsMilliTime - sysTime) * 1000)
    local dateTime = os.date("%Y-%m-%d %H:%M:%S.", sysTime) .. millisecond
    return dateTime
end

-- 预处理设置信息
local function preSetInfo()
    session:execute("export", "fuuid=" .. fUuid)
    session:execute("set", "ringback=${us-ring}")
    session:execute("set", "api_hangup_hook=lua prison_hangup.lua " .. fUuid .. " " .. prisonExten)
end

-- 根据民警分机号，获取民警分机通道UUID
local function getPoliceUUIDByNum()
    local uuid
    local res = api:executeString("show channels like " .. policeExtenNo .. "@ as xml")
    if res then
        _, _, uuid = string.find(res, "<uuid>(.-)<%/uuid>")
    end
    return uuid;
end

-- 获取对应编号的亲属号码
local function getCurRelavtiveByBtnNo(btnNum)
    -- 按键编号
    for i = 1, #prisonInfo.relatives do
        local numIndex = prisonInfo.relatives[i].serialnumber;
        if btnNum == numIndex then
            return prisonInfo.relatives[i];
        end
    end
    return nil
end

-- 获取民警监听状态
local function policeMonitorStatus()
    -- 定义返回值
    local retStatus = true;
    -- 构造请求参数
    local prisonExtenParam = "extensionnumber=" .. prisonExten
    local prisonCodeParam = "Prison_Code=" .. prisonCode
    local APIParams = prisonExtenParam .. "&" .. prisonCodeParam
    -- 构造请求地址
    local APIUrl = apiUrl .. "/api/PBXAuthentication/UserSuspend"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " post " .. APIParams)
    freeswitch.consoleLog("INFO", "policeMonitorStatus resultData : " .. resultData .. "\n")
    -- 解析json字符串
    local msgObj = cJson:decode(resultData)

    if msgObj == nil or msgObj == "" then
        freeswitch.consoleLog("WARNING", "policeMonitorStatus *** 调用失败 ***\n")
        session:hangup()
        retStatus = false;
        return retStatus;
    end

    local code = msgObj.code
    if code ~= 0 then
        session:streamFile("custom/userSuspends.wav")
        session:hangup()
        retStatus = false;
    end
    -- 返回当前语句可用状态
    return retStatus
end

-- 验证民警分机以及监听状态
local function checkPoliceStatus()
    -- 添加数量
    local nAddNum = 10 ^ (string.len(prisonExten) - 1)
    -- 民警分机号
    local policeExten = tostring(tonumber(prisonExten) + nAddNum)
    freeswitch.consoleLog("INFO", "checkPoliceStatus 对应的民警分机号：" .. policeExten .. "\n")
    -- 赋值全局的民警分机号
    policeExtenNo = policeExten;

    -- 验证民警分机监听状态
    local retStatus = policeMonitorStatus()

    if retStatus == true then
        local exeStr = "originate {fuuid=" .. fUuid .. "}user/" .. policeExten .. "@" .. domain .. " &eavesdrop(" ..
                           fUuid .. ")"
        local tmpstr = api:executeString(exeStr)
        freeswitch.consoleLog("INFO", "连接民警分机字符串：" .. exeStr .. " ----- " .. tmpstr .. "\n")
        -- 如果连接失败
        if string.sub(tmpstr, 1, 4) == "-ERR" then
            freeswitch.consoleLog("WARNING", "checkPoliceStatus 民警分机可能未登录：" .. policeExten .. "\n")
            session:streamFile("custom/not_useful.wav")
            session:hangup()
            return false
        end
    end

    return retStatus;
end

--  罪犯编号登录
local function prisonLogin(prisonNo)
    -- 构造请求参数
    local prisonNoParam = "number=" .. prisonNo
    local prisonExtenParam = "extensionnumber=" .. prisonExten
    local prisonCodeParam = "Prison_Code=" .. prisonCode
    local APIParams = prisonNoParam .. "&" .. prisonExtenParam .. "&" .. prisonCodeParam
    -- 构造请求地址
    local APIUrl = apiUrl .. "/api/PBXAuthentication/PrisonLogin"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " post " .. APIParams)
    freeswitch.consoleLog("INFO", "prisonlogin resultData : " .. resultData .. "\n")
    -- 解析json字符串
    local retObj = cJson:decode(resultData)

    if retObj == nil or retObj == "" then
        freeswitch.consoleLog("WARNING", "prisonlogin 接口调用失败  ***\n")
        session:hangup()
        return false
    end

    local code = retObj.code
    if code == 1001 then
        -- 提示：“编号不存在，请确认后，请重新输入”
        session:streamFile("custom/num_is_not_exit.wav")
        return false
    elseif code == 2001 then
        -- 提示：“您没有绑定的亲属”
        session:streamFile("custom/no_family_bind.wav")
        return false
    elseif code == 2002 then
        -- 提示：“您绑定的亲属没有电话拨打权限”
        session:streamFile("custom/no_family_allow.wav")
        return false
    end

    if code ~= 0 then
        -- 提示：“查询编号错误”
        session:streamFile("custom/query_num_error.wav")
        return false
    end

    local prisonData = retObj.data

    -- 是否禁用拨打
    local isDisable = false
    if  nil ~= prisonData.teldisable then        
        isDisable = prisonData.teldisable
    end

    if true == isDisable then
        freeswitch.consoleLog("Notice", "管理员禁用亲情电话拨打\n")
        session:streamFile("custom/mgr_disable.wav")
        session:hangup()
        return false
    end

    prisonInfo.pwd = prisonData.pwd
    -- 剩余拨打次数
    prisonInfo.callTime = prisonData.number
    -- 拨打最长分钟数
    prisonInfo.maxdur = prisonData.talktime
    -- 电话余额
    prisonInfo.surplustime = prisonData.surplustime
    -- 是否开启倒计时
    prisonInfo.isCountdown = prisonData.iscountdown
    -- 赋值亲属列表
    prisonInfo.relatives = prisonData.relatives
    return true
end

-- 请输入罪犯应用编号
local function pleaseInputNo()
    session:streamFile("custom/input_num.wav")
    for i = 1, 3 do
        session:sleep(1000)
        prisonBusNo = session:playAndGetDigits(prison_no_len_min, prison_no_len_max, 1, 5000, "#", "", "", "\\d+") or "";
        if prisonBusNo == "" then
            -- 提示：“请输入你的编号”
            session:streamFile("custom/input_num.wav")
        else
            -- 根据输入的编号，执行登录
            if prisonBusNo ~= "" and prisonLogin(prisonBusNo) == true then
                break
            end
        end

        if i == 3 then
            session:hangup()
            return
        end
    end
end

-- 请输入罪犯应用密码
local function pleaseInputPwd()
    if prisonInfo.pwd == nil or prisonInfo.pwd == "" then
        return false
    end
    -- 密码不为空则，提示输入密码
    session:streamFile("custom/input_pwd.wav")
    for i = 1, 3 do
        -- session:sleep(2000)
        local inputValue = session:playAndGetDigits(0, 11, 1, 5000, "#", "", "", "\\d+");
        if inputValue == prisonInfo.pwd then
            break
        end

        -- 提示：“密码错误，请重新输入”
        session:streamFile("custom/wrong_pwd.wav")
        freeswitch.consoleLog("WARNING", "罪犯输入密码错误：" .. inputValue .. "\n")
        -- 错误次数大于等于三次->挂机
        if i == 3 then
            session:hangup()
            return false
        end
    end
    return true;
end

-- 播报联系人列表
local function playContactList()
    for i = 1, #prisonInfo.relatives do
        local relativeObj = prisonInfo.relatives[i]
        -- 提示：“联系人 1，18800880088”
        session:streamFile("custom/contact.wav")
        api:executeString("uuid_broadcast " .. fUuid .. " custom/digits/" .. relativeObj.serialnumber .. ".wav both")
        session:sleep(1000)
        session:say(relativeObj.telephonenumber, "en", "name_spelled", "iterated")
    end
end

-- 播报余额
local function playCurrentBalance()
    local zsBalance = 0;
    local xsBalance = 0;
    if prisonInfo.surplustime < 0 then
        prisonInfo.surplustime = 0
    end
    -- 取整数 和 小数
    zsBalance, xsBalance = math.modf(prisonInfo.surplustime)
    xsBalance = math.floor(xsBalance * 100)
    local isXsSimpleNum = false
    if 0 < xsBalance and xsBalance < 10 then
        isXsSimpleNum = true
    end

    -- 小数部分一个被10整除的十位数
    if 0 == xsBalance % 10 then
        xsBalance = xsBalance / 10
    end
    freeswitch.consoleLog("NOTICE", "zsBalance : " .. zsBalance .. ", xsBalance = " .. xsBalance .. "\n")
    session:streamFile("custom/balance.wav")
    -- 读小数部分
    session:say(zsBalance, "zh", "number", "pronounced")
    -- 读小数部分
    if 0 < xsBalance then
        session:streamFile("digits/dot.wav")
        -- 如果是“分”单位的小数，前面加0            
        if isXsSimpleNum then
            session:streamFile("digits/0.wav")
        end
        session:say(xsBalance, "zh", "number", "iterated")
    end
    session:streamFile("custom/yuan.wav")
end

-- 请求修改罪犯话机密码
local function askModifyPhonePwd(newPwd)
    -- 构造请求参数
    local prisonNoParam = "number=" .. prisonBusNo
    local prisonCodeParam = "jxCode=" .. prisonCode
    local newPwd = "newPwd=" .. newPwd
    local APIParams = prisonNoParam .. "&" .. prisonCodeParam .. "&" .. newPwd
    -- 构造请求地址
    local APIUrl = apiUrl .. "/api/PBXAuthentication/ChangePhonePassword"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " post " .. APIParams)
    freeswitch.consoleLog("INFO", "prison modify pwd resultData : " .. resultData .. "\n")
    -- 解析json字符串
    local retObj = cJson:decode(resultData)

    if retObj == nil or retObj == "" then
        freeswitch.consoleLog("WARNING", "askModifyPhonePwd 接口调用失败  ***\n")
        session:hangup()
        return false
    end

    local code = retObj.code
    if code ~= 0 then
        -- 提示：密码修改失败，请联系管理员，或重新设置
        session:streamFile("custom/pwd_modfiy_error.wav")
        return false
    end

    -- 提示：密码修改成功
    session:streamFile("custom/pwd_modfiy_ok.wav")
    -- 保存新密码到存储的罪犯信息中
    prisonInfo.pwd = newPwd
    return true
end

-- 修改密码
local function processModifyPwd()
    session:flushDigits()
    -- 提示：请输入您要设置的6位数新密码(等待时间20秒)
    local newPwdWord = session:playAndGetDigits(prison_new_pwd_len, prison_new_pwd_len, 1, 15000, "*#",
        "custom/input_new_pwd.wav", "", "");
    local newPwdNum = tonumber(newPwdWord)
    if (nil == newPwdNum) then
        -- 提示：密码必须是6位数字，# * 设置无效，请求重新设置
        session:streamFile("custom/new_pwd_error.wav")
        -- 等待2秒
        session:sleep(2000)
        -- 等待2秒后，重新提示设置密码
        processModifyPwd()
        return
    end

    session:sleep(1000)
    -- 在缓冲区已经存在内容后（操作才生效）
    session:flushDigits()
    -- 提示：请再次输入新密码
    local makeSurePwd = session:playAndGetDigits(prison_new_pwd_len, prison_new_pwd_len, 1, 15000, "*#",
        "custom/input_new_pwd_sure.wav", "", "");
    if newPwdWord ~= makeSurePwd then
        -- 提示：两次密码输入不一致，请重新设置
        session:streamFile("custom/pwd_sure_error.wav")
        -- 等待2秒
        session:sleep(2000)
        -- 等待2秒后，重新提示设置密码
        processModifyPwd()
        return
    end

    -- 调用请求修改密码接口
    askModifyPhonePwd(newPwdWord)
    return
end

local function helpKeyProcess()
    -- 提示：“查询联系人列表请按0，查询剩余拨打次数请按 #91, ...”
    local helpKeyBtn = session:playAndGetDigits(0, 3, 1, 3000, "", "custom/input_query.wav", "", "");
    -- 处理功能按键
    if helpKeyBtn == "#91" then
        -- 当前余额播报
        playCurrentBalance()
    elseif helpKeyBtn == "#92" then
        if prisonInfo.callTime > 0 then
            -- 剩余拨打次数
            session:streamFile("custom/crt.wav")
            session:say(prisonInfo.callTime, "en", "number", "pronounced")
        else
            -- 拨打次数为0
            session:streamFile("custom/crt_0.wav")
        end
    elseif helpKeyBtn == "#93" then
        -- 判断是否允许本次拨打
        if prisonInfo.callTime > 0 then
            -- 当前号码允许本次拨打
            session:streamFile("custom/allow.wav")
        else
            -- 当前号码没有权限,不允许本次拨打
            session:streamFile("custom/not_allow.wav")
        end
    elseif helpKeyBtn == "#94" then
        -- 处理修改电话密码
        processModifyPwd()
    elseif helpKeyBtn == "0" then
        -- 执行播报联系人
        playContactList()
    end
end

-- 充值会议的开始时间参数（）
local function resetConfBeginTime(confName)
    -- 重置通话开始时间（避免定时任务处理此通话，最大时长）
    local hashKey = "insert/" .. confName .. "/begintime/" .. 0
    api:executeString("hash " .. hashKey)
    freeswitch.consoleLog("INFO", "reset beginTime confName : " .. confName .. " beginTime : " .. 0 .. "\n")
end

-- 初始化会议的时间参数
local function initConfTime(confName)
    -- 设置操作开始时间
    local nowTime = os.time()
    local hashKey = "insert/" .. confName .. "/actiontime/" .. nowTime
    api:executeString("hash " .. hashKey)
    freeswitch.consoleLog("INFO", "confName : " .. confName .. " actionTime : " .. nowTime .. "\n")

    -- 如果存在最大通话时长，记录
    if prisonInfo.maxdur ~= "" then
        local maxMin = tonumber(prisonInfo.maxdur) or 0
        local hashKey = "insert/" .. confName .. "/maxdur/" .. maxMin
        api:executeString("hash " .. hashKey)
        freeswitch.consoleLog("INFO", "init actionTime confName : " .. confName .. " maxdur : " .. maxMin .. "\n")
    end

    -- 设置录音时间
    hashKey = "insert/" .. fUuid .. "/recordTime/" .. nowTime
    api:executeString("hash " .. hashKey)
end

-- 发送redis 队列消息
local function sendRedisMsg(msgObj)
    -- 定义返回值
    local retStatus = true;
    -- 构造请求参数
    local jsonParams = cJson:encode(msgObj)
    -- 构造请求地址
    local APIUrl = aisWebUrl .. "/send/redis/add/ws"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " content-type application/json post '" .. jsonParams .. "'")
    freeswitch.consoleLog("INFO", "sendRedisMsg resultData : " .. resultData .. "\n")
    -- 解析json字符串
    local resultObj = cJson:decode(resultData)

    if resultObj == nil or resultObj == "" then
        freeswitch.consoleLog("WARNING", "sendRedisMsg *** 调用失败 ***\n")
        session:hangup()
        retStatus = false;
        return retStatus;
    end

    local code = tonumber(resultObj.code)
    if code ~= 200 then
        retStatus = false;
    end
    -- 返回当前语句可用状态
    return retStatus
end

-- 罪犯分机发起会议
local function addPrisonJoinConf(confName, relaPhone)
    -- 将罪犯分机转进会议
    session:execute("lua", "asr.lua " .. confName .. " caller " .. relaPhone)
    local recordName = confName .. "-" .. relaPhone
    -- 会议录音
    session:execute("lua", "record_conference.lua " .. recordName .. " " .. confName)
    freeswitch.consoleLog("WARNING", "conference start, Add Prison JOIN, prisonExten : " .. prisonExten .. "\n")
    -- 通过Session 连接到会议
    session:execute("conference", string.format("%s@PrisonConfig+flags{dist-dtmf}", confName))
    -- 通过API连接到会议(发起呼叫)
    -- api:executeString("uuid_transfer " .. fUuid .. " " .. confName .. "@PrisonConfig+flags{}")
end

-- 添加主持人进入会议
local function addPoliceJoinConf(confName)
    -- 邀请管理员进入会议，并设置成主持人
    local policeChannelUuid = getPoliceUUIDByNum()
    -- 如果民警分机正在通话中
    if policeChannelUuid ~= "" and policeChannelUuid ~= nil then
        -- 设置民警分机通道ID
        local hashKey = "insert/" .. fUuid .. "/policeId/" .. policeChannelUuid
        api:executeString("hash " .. hashKey)
        -- 如果找到民警分机通道编号（注意 context 参数是必要参数）
        api:executeString("uuid_transfer " .. policeChannelUuid .. " " .. confName ..
                              "@PrisonConfig+flags{moderator|ghost|endconf|nomoh|mute}" .. " XML " .. context)
        freeswitch.consoleLog("WARNING", "conference uuid_transfer policeChannelUuid : " .. policeChannelUuid .. "\n")
    else
        -- 如果民警分机没有在通话或者监听状态，发起呼叫民警分机
        api:executeString("conference " .. confName ..
                              "@PrisonConfig+flags{moderator|ghost|endconf|nomoh|mute} dial {ignore_early_media=false}user/" ..
                              policeExtenNo .. "@" .. domain)
        freeswitch.consoleLog("WARNING", "conference link policeExtenNo : " .. policeExtenNo .. "\n")
    end
end

-- 添加亲属外线成员进入会议
local function addRelativeJoinConf(confName, relaPhone)
    -- create_uuid
    local destUuid = api:executeString("create_uuid")
    local haskKey = "insert/" .. confName .. "/dest/" .. destUuid
    api:executeString("hash " .. haskKey)

    -- 定义Answer 后回调执行
    local exeOnAnswerStr = "execute_on_answer='lua asr.lua " .. confName .. " dest " .. relaPhone .. "'";

    if string.find(gatewayName, "user/") then
        -- user/Jixun (网关 -> FS 注册)
        api:executeString("conference " .. confName ..
                              "@PrisonConfig+flags{mintwo|join-only|dist-dtmf} bgdial {bridge_early_media=true,ignore_early_media=false,caller_id_number=" ..
                              confName .. "," .. exeOnAnswerStr .. ",origination_uuid=" .. destUuid .. ",fuuid=" ..
                              fUuid .. ",dest_real_number=" .. relaPhone .. "}" .. gatewayName)
        freeswitch.consoleLog("WARNING", "conference with USER/GW link relaPhone : " .. relaPhone .. "\n")
    else
        -- sofia/gateway/gw-demo/ (FS -> 网关 注册)        
        api:executeString("conference " .. confName ..
                              "@PrisonConfig+flags{mintwo|join-only|dist-dtmf} bgdial {bridge_early_media=true,ignore_early_media=false,caller_id_number=" ..
                              confName .. "," .. exeOnAnswerStr .. ",origination_uuid=" .. destUuid .. ",fuuid=" ..
                              fUuid .. "}" .. gatewayName .. relaPhone)
        freeswitch.consoleLog("WARNING", "conference with SOFIA/GW link relaPhone : " .. relaPhone .. "\n")
    end
    -- 初始化会议相关时间
    initConfTime(confName)
end

-- 开始发起三方会议呼叫
local function startPrisonConference(curRelative)
    -- 构造要发送的Redis数据
    local msgObj = {};
    msgObj.callid = fUuid
    msgObj.fuuid = fUuid
    msgObj.cmd = "prison_dial"
    msgObj.tel_number = curRelative.telephonenumber
    msgObj.caller = prisonBusNo
    msgObj.userid = prisonExten
    msgObj.kinship = curRelative.kinship
    -- 发送消息(输入有效的亲属编号后，通知业务系统)
    sendRedisMsg(msgObj)

    -- 设置会议名称（会议参数）
    local confName = confNameHeader .. prisonExten
    -- 初始化时间
    resetConfBeginTime(confName)
    -- 提示：“请销后”
    session:streamFile("custom/outline.wav")
    local relaPhone = curRelative.telephonenumber
    -- 邀请三方加入会议
    addPoliceJoinConf(confName)
    addRelativeJoinConf(confName, relaPhone)
    addPrisonJoinConf(confName, relaPhone)
end

-- 通过编号，呼叫亲属
local function callRelative(nKey)
    -- 根据编号获取亲属信息
    local curRelative = getCurRelavtiveByBtnNo(nKey)
    -- 如果亲属信息编号不存在，返回重新进入IVR
    if nil == curRelative then
        return false;
    end

    freeswitch.consoleLog("INFO", "curRelative : " .. cJson:encode(curRelative) .. "\n")

    -- 验证亲属是否被禁用
    if nil ~= curRelative.telstatus then
        local isDisable = curRelative.telstatus
        -- 如果亲属被禁用，提示用户并挂机
        if true == isDisable then
            session:streamFile("custom/relative_diable.wav")
            session:hangup()
            return true
        end
    end

    -- 验证罪犯：剩余拨打次数
    if prisonInfo.callTime <= 0 then
        session:streamFile("custom/call_time_none.wav")
        session:hangup()
        return true
    end

    -- 验证罪犯：电话余额
    if prisonInfo.surplustime <= 0 then
        session:streamFile("custom/has_not_balance.wav")
        session:hangup()
        return true
    end

    -- 开始发起会议
    startPrisonConference(curRelative);
    -- 一通电话完成后，挂断通话
    session:hangup()
    -- 一定要return, 否则某些情况下可能存在，可以重复继续拨号的情况。   
    return true
end

-- 功能处理
local function futureProcess()
    callFutureTime = callFutureTime + 1;
    if callFutureTime >= 30 then
        return false;
    end
    -- 间隔一定时间播报
    session:sleep(50);
    -- 提示：“请输入亲属编号或者查询编号，如需帮助请按*号键”
    local keyBtn = session:playAndGetDigits(0, 3, 1, 3000, "#", "custom/button.wav", "", "");
    -- 超时未输入重新提示
    if keyBtn == "" or keyBtn == nil then
        futureProcess();
    end

    -- 帮助按键操作
    if keyBtn == "*" then
        -- 执行帮助按键
        helpKeyProcess()
        -- 完成后，继续执行外面的IVR提示
        futureProcess()
    else
        -- 把输入转换为数字
        local nKey = tonumber(keyBtn);
        -- 如果按键错误，重新进入操作提示音
        if nKey == nil or 0 > nKey then
            futureProcess()
        end

        -- 呼叫相应的亲属。如果亲属编号不存在，你们重新发起IVR提示音
        if callRelative(nKey) == false then
            futureProcess()
        end
    end
end

local function sendPrisonOkRedisMsg()
    -- 发送请求通知redis -->  服务一直获取redis 消息，如果存在“fs_queue” 消息，则推送 publish
    -- 构造要发送的Redis数据
    local msgObj = {};
    msgObj.callid = fUuid
    msgObj.fuuid = fUuid
    msgObj.modename = "surplustime"
    msgObj.caller = prisonBusNo
    msgObj.userid = prisonExten
    -- 验证罪犯信息正确后，发送通知消息
    sendRedisMsg(msgObj)
end

-- 发送新的呼叫中发起呼叫的标识
local function sendAisCallCenterFlag()
    -- 发送请求通知redis -->  服务一直获取redis 消息，如果存在“fs_queue” 消息，则推送 publish
    -- 构造要发送的Redis数据
    local msgObj = {};
    msgObj.fuuid = fUuid
    msgObj.cmd = "aisFlag"
    sendRedisMsg(msgObj)
end

-- 设置一些信息
preSetInfo()
-- 发送AisFlag
sendAisCallCenterFlag()
-- 分机应答
session:answer()
session:sleep(50)
-- 执行：验证民警分机以及监听状态
if true == checkPoliceStatus() then
    -- 执行：输入编号
    pleaseInputNo()
    -- 执行：输入密码
    local checkState = pleaseInputPwd()
    -- 如果密码都验证正确，那么执行一下步骤
    if true == checkState then
        -- 发送罪犯信息验证正确
        sendPrisonOkRedisMsg();
        -- 进入IVR处理功能按键操作
        futureProcess();
    end
end

