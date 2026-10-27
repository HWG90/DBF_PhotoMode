local View=dofile('freecam/vendor/view.lua')
local world={};local draws,binds,queries,destroyed=0,0,0,0
local font={font='28a718e0d452eff0',atlas='c2cffd6538624e20',material='c38a65a21fb3e8d0'}
local G={resolution=function()return 1280,720 end}
function G.material(gui,name)
 queries=queries+1;assert(gui.materials[name],'Never query an unassigned material')
 return gui.materials[name]
end
function G.text(gui,text,face,size,material)
 assert(text=='Actual menu text','Never allocate an invisible seed label')
 assert(face==font.font and material==font.material)
 gui.materials[material]=gui.materials[material]or{}
 draws=draws+1;return draws
end
function G.destroy_text()destroyed=destroyed+1 end
local sr={Gui=G,Application={worlds=function()return{world}end,main_world=function()return world end},
 World={create_screen_gui=function()return{materials={}}end,destroy_gui=function()end},
 IdString64={from_hex=function(x)return x end},Material={set_texture=function(handle,slot,atlas)assert(atlas==font.atlas);binds=binds+1 end},
 Vector2=function(...)return{...}end,Vector3=function(...)return{...}end,Color=function(...)return{...}end}
local view=View.new(sr,true);view._accept_font(font)
local commands={{type='text',text='Actual menu text',x=10,y=10,size=14,a=1,c={255,255,255}}};local token={}
assert(view.draw(commands,token)~=false);assert(draws==1 and queries==1 and binds==1,'First real text assigns then binds the game material')
for i=1,20 do assert(view.draw(commands,token)~=false)end
assert(draws==1,'Retained font geometry must not be recreated')
assert(view.font_key:find(font.font,1,true),'Keep the game face, not the debug fallback')
assert(view.release()~=false and destroyed==1)
print('Windows font GUI: no create_material, no unassigned query, real first text only, atlas binding and retained idle passed')
