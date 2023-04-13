local api = freeswitch.API()
-- 加载JSON模块
local cJson = freeswitch.JSON()
-- 获取通道中的变量
local policeExtensionNo = session:getVariable("caller_id_number")
local apiUrl = session:getVariable("Prison_ApiUrl")
local prisonCode = session:getVariable("Prison_Code")

-- 民警编号长度定义
local police_no_len_min = 3
local police_no_len_max = 8

-- 定义获取输入的民警编号 变量
local policeNo = ""

local function policeLogin(policeNo)
    -- 构造请求参数
    local policeNoParam = "number=" .. policeNo
    local extensionParam = "extensionnumber=" .. policeExtensionNo
    local typeParam = "type=1"
    local prisonCodeParam = "Prison_Code=" .. prisonCode
    local APIParams = policeNoParam .. "&" .. extensionParam .. "&" .. typeParam .. "&" .. prisonCodeParam
    -- 构造请求地址
    local APIUrl = apiUrl .. "/api/PBXAuthentication/PoliceLogin"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " post " .. APIParams)

    -- 返回空或者调用失败直接挂机
    if resultData == nil or resultData == "" then
        freeswitch.consoleLog("INFO", "policeLogin  接口调用失败  *************\n")
        session:hangup()
        return
    end

    freeswitch.consoleLog("INFO", "policeLogin 接口返回：" .. resultData .. "\n")
    -- 解析json字符串
    local rstObj = cJson:decode(resultData)
    -- 返回解析失败
    if rstObj == nil or rstObj == "" then
        freeswitch.consoleLog("INFO", "policeLogin  接口返回值解析失败  *************\n")
        session:hangup()
        return
    end

    -- 状态错误，返回false
    local resultCode = rstObj.code;
    if resultCode ~= 0 then
        return false
    end

    return true
end

-- 提示：“请输入您的编号”
session:streamFile("custom/input_num.wav")
for i = 1, 3 do
    session:sleep(1000)
    policeNo = session:playAndGetDigits(police_no_len_min, police_no_len_max, 1, 5000, "#", "", "", "\\d+") or "";
    -- 验证民警编号登录
    if policeNo ~= "" and policeLogin(policeNo) == true then
        -- 提示：“管理员已登录”
        session:streamFile("custom/admin_login.wav")
        break
    end
    -- 提示：“编号不存在”
    session:streamFile("custom/num_is_not_exit.wav")
end

-- 登录操作完成
session:hangup();
