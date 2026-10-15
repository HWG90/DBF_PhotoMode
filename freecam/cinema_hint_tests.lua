local root=rawget(_G,'DBF_PHOTO_TEST_ROOT')or'freecam/'
local commands
local menu=assert(loadfile(root..'photo_menu.lua'))().new({draw=function(v)commands=v end},{})
local function draw(age,hidden)
 menu.draw_cinema(1920,1080,'Caps Lock',hidden,age)
 return commands
end
assert(#draw(0)==4 and commands[3].a==1,'A new action shot needs its short controls hint')
assert(#draw(2)==4 and commands[3].a==1,'The hint must remain readable before fading')
assert(#draw(2.5)==4 and commands[3].a==.5 and math.abs(commands[1].a-.34)<1e-9,'All hint layers must fade together')
assert(#draw(3)==0 and #draw(60)==0,'The hint must clear completely after three seconds')
assert(#draw(0,true)==0,'Hidden controls and screenshot capture must suppress the hint')
assert(#draw(10)==0,'Returning from a screenshot must not restart an expired hint')
assert(#draw(nil)==0 and #draw(0/0)==0 and #draw(-1)==0,'Missing or invalid timing must not leave a permanent badge')
assert(#draw(0)==4,'A later action shot must show its own fresh hint')
print('Cinema hint: entry visibility, synchronized fade, expiry, hidden capture and invalid timing passed')
