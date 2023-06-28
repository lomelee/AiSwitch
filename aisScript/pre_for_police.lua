-- pre_for_police.lua 
-- 判断主叫用户是否是 Police 
-- 非管理员挂断 
local api = freeswitch.API()

local domain = session:getVariable("domain_name") or session:getVariable("local_ip_v4")
--  ${caller_id_number}  主叫分机号码
local caller = session:getVariable("caller_id_number")

-- 定义处理类型
local preType = argv[1] or "login";

-- 先应答，否则挂断时Freeswitch要发送480到客户端
session:answer()
-- ${user_data(${caller_id_number}@${domain_name} var is_Police)}   获取用户参数
local isPolice = api:execute("user_data", caller .. "@" .. domain .. " var is_police") or "false"
if isPolice == "1" then
    freeswitch.consoleLog("info", caller .. " is a police. \n")
    if preType == "login" then
        -- 执行民警登录业务脚本
        session:execute("lua", "police_login.lua")
    elseif preType == "logout" then
        -- 执行民警登出业务脚本
        session:execute("lua", "police_logout.lua")
    end
else
    freeswitch.consoleLog("info", caller .. " is not a police, then hangup. \n")    
    session:sleep(1000)
    -- 提示：“非管理员不允许操作”
    session:streamFile("custom/is_not_admin_so_deny.wav")
    session:sleep(2000)
    session:hangup()
end
