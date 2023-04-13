aisUtils = {}
-- URL Encode （URL 编码工具类）
--
-- Can take a table, or a string of comma separated values.
-- Examples:
-- > print(uriEncode("this=is,a=/test/,string='quotes'"))
-- a=%2Ftest%2F&string=%27quotes%27&this=is
-- > print(uriEncode({this="is", a="/test/", string="'quotes'"}))
-- a=%2Ftest%2F&string=%27quotes%27&this=is
--

local function escape(s)
    s = string.gsub(s, '([\r\n"#%%&+:;<=>?@^`{|}%\\%[%]%(%)$!~,/\'])', function(c)
        return '%' .. string.format("%02X", string.byte(c));
    end);
    s = string.gsub(s, "%s", "+");
    return s;
end

local function encode(t)
    local s = "";
    for k, v in pairs(t) do
        s = s .. "&" .. escape(k) .. "=" .. escape(v);
    end
    return string.sub(s, 2);
end

function aisUtils.uriEncode(vals)
    if type(vals) == 'table' then
        return encode(vals);
    else
        local t = {};
        for k, v in string.gmatch(vals, ",?([^=]+)=([^,]+)") do
            t[k] = v;
        end
        return encode(t);
    end
end

return aisUtils