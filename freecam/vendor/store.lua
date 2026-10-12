-- Separate per-mod INI-like value files; no executing configuration as Lua.
local M={}
function M.new(folder)
    local self={}
    local function path(id)assert(id:match('^[%w_-]+$'));return folder..'/'..id..'.ini'end
    function self.load(id)
        local values={};local f=io.open(path(id),'rb');if not f then return values end
        local data=f:read(65537);f:close();if #data>65536 then return values end
        for key,value in data:gmatch('([%w_-]+)=([^\r\n]+)')do
            if value:match('^@[%w _-]+$') then values[key]=value:sub(2) elseif value=='true' then values[key]=true elseif value=='false' then values[key]=false
            elseif value:match('^#%x%x%x%x%x%x$') then values[key]=value:upper()
            else local n=tonumber(value);if n and n==n and math.abs(n)<1e12 then values[key]=n end end
        end
        return values
    end
    function self.save(id,values)
        local target=path(id);local temp,backup=target..'.tmp',target..'.bak';local rows={}
        for key,value in pairs(values)do
            assert(key:match('^[%w_-]+$') and (type(value)=='boolean' or type(value)=='number' or (type(value)=='string' and (value:match('^#%x%x%x%x%x%x$') or (#value<=48 and value:match('^[%w _-]+$'))))),'Invalid persisted value')
            rows[#rows+1]=key..'='..(type(value)=='string' and value:sub(1,1)~='#' and '@'..value or tostring(value))..'\n'
        end
        table.sort(rows);local f,err=io.open(temp,'wb');if not f then return false,err end
        local ok,write_err=f:write(table.concat(rows));local closed,close_err=f:close()
        if not ok or not closed then os.remove(temp);return false,write_err or close_err end
        local old=io.open(target,'rb');if old then old:close();os.remove(backup)
            local moved,why=os.rename(target,backup);if not moved then os.remove(temp);return false,why end end
        local moved,why=os.rename(temp,target)
        if not moved then if old then os.rename(backup,target)end;return false,why end
        return true
    end
    return self
end
return M
