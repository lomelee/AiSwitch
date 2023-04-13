local api = freeswitch.API()
-- 加载JSON模块
local cJson = freeswitch.JSON()
-- 获取通道中的变量
local policeExtensionNo = session:getVariable("caller_id_number")
local apiUrl = session:getVariable("Prison_ApiUrl")
local prisonCode = session:getVariable("Prison_Code")

-- 民警登出
local function policeLogout(policeNoParam)
    -- 构造请求参数
    local numParam = "number=" .. policeNoParam
    local extensionParam = "extensionnumber=" .. policeExtensionNo
    local typeParam = "type=2"
    local prisonCodeParam = "Prison_Code=" .. prisonCode
    local APIParams = numParam .. "&" .. extensionParam .. "&" .. typeParam .. "&" .. prisonCodeParam
    -- 构造请求地址
    local APIUrl = apiUrl .. "/api/PBXAuthentication/PoliceLogin"
    -- 发起请求
    local resultData = api:execute("curl", APIUrl .. " post " .. APIParams)

    -- 返回空或者调用失败直接挂机
    if resultData == nil or resultData == "" then
        freeswitch.consoleLog("INFO", "policeLogout  接口调用失败  *************\n")
        session:hangup()
        return
    end

    freeswitch.consoleLog("INFO", "policeLogout 接口返回：" .. resultData .. "\n")
    -- 解析json字符串
    local rstObj = cJson:decode(resultData)
    -- 返回解析失败
    if rstObj == nil or rstObj == "" then
        freeswitch.consoleLog("INFO", "policeLogout  接口返回值解析失败  *************\n")
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

-- 获取hash中存放的分机对应的民警编号
local selKey = "select/" .. policeExtensionNo .. "/police_num/"
local policeNo = api:executeString("hash " .. selKey) or ""

-- 执行民警退出登录
if policeNo ~= "" and true == policeLogout(policeNo) then
    -- 删除hash中存放的分机对应的民警编号
    local hashkey = "delete/" .. policeExtensionNo .. "/police_num"
    api:executeString("hash " .. hashkey)

    -- 提示：“管理员已登出”
    session:streamFile("custom/admin_logout.wav")
    freeswitch.consoleLog("INFO", "民警退出登录，编号: " .. policeNo .. ", 分机号：" .. policeExtensionNo .. "\n")
end

-- 操作完成
session:hangup();
