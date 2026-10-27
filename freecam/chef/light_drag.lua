-- Explicit clutch + middle-button dragging in the camera plane. Only at most
-- three projected owned markers are considered on press; no scene inventory.
local M={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e7 end
function M.new(chef,lights)
    local self={};local drag,down,fault=nil,false,false
    function self.reset() drag=nil;down=false;fault=false end
    local function fail(why) drag=nil;fault=true;return false,why end
    function self.tick(pressed,fine,view)
        if not pressed then self.reset();return false end
        if fault then return false end
        if type(chef.cursor)~='function' or type(chef.world_to_screen)~='function' then return fail('Chef marker input unavailable') end
        local x,y=chef.cursor();local w,h=chef.screen()
        if not finite(x) or not finite(y) or not finite(w) or not finite(h) or w<=0 or h<=0 then return fail('Marker cursor unavailable') end
        if not down then
            local best,distance=nil,18^2
            for _,marker in ipairs(lights.markers()) do
                local p=marker.position;local sx,sy=chef.world_to_screen(p[1],p[2],p[3])
                if finite(sx) and finite(sy) then
                    local d=(x-sx)^2+(y-sy)^2
                    if d<=distance then best,distance=marker,d end
                end
            end
            if best then
                local depth=0;for i=1,3 do depth=depth+(best.position[i]-view.position[i])*view.forward[i] end
                if depth>.05 then drag={slot=best.slot,position={unpack(best.position)},scale=2*depth*math.tan(view.fov/2)/h,
                    right={unpack(view.right)},up={unpack(view.up)},w=w,h=h,x=x,y=y} end
            end
        end
        down=true
        if not drag then return false end
        if w~=drag.w or h~=drag.h then return fail('Marker drag ended after resize') end
        local dx,dy=x-drag.x,y-drag.y;drag.x,drag.y=x,y
        if dx==0 and dy==0 then return true end
        local scale=drag.scale*(fine and .1 or 1)
        for i=1,3 do drag.position[i]=drag.position[i]+(drag.right[i]*dx+drag.up[i]*dy)*scale end
        local ok,why=lights.move(drag.slot,drag.position)
        if not ok then return fail(why) end
        return true
    end
    return self
end
return M
