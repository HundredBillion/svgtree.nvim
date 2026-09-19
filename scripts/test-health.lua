vim.opt.runtimepath:prepend(vim.fn.getcwd())
local config=require('svgtree.config')
local capability=require('svgtree.capability')
local raster=require('svgtree.raster')
local original_health, original_terminal, original_converter=vim.health,capability.terminal_supported,raster.has_converter
local original_executable=vim.fn.executable
local original_img=vim.ui.img
vim.ui.img=false
local calls={}
vim.health={start=function() end,ok=function(s) calls[#calls+1]={'ok',s} end,
  warn=function(s) calls[#calls+1]={'warn',s} end,error=function(s) calls[#calls+1]={'error',s} end,
  info=function(s) calls[#calls+1]={'info',s} end}
capability.terminal_supported=function() return false end
raster.has_converter=function() return false end
vim.fn.executable=function() return 0 end
local function run(renderer,api)
  config.options.renderer=renderer
  package.loaded.sprite=api and {available=function() end} or nil
  calls={}
  require('svgtree.health').check()
  return calls
end
local native=run('auto',true)
for _,call in ipairs(native) do assert(call[1]~='error' and call[1]~='warn',call[2]) end
assert(vim.iter(native):any(function(call) return call[2]:find('Sprite plugin API found',1,true) end))
local terminal=run('terminal',false)
assert(vim.iter(terminal):any(function(call) return call[1]=='error' and call[2]:find('vim.ui.img',1,true) end))
assert(vim.iter(terminal):any(function(call) return call[1]=='error' and call[2]:find('converter',1,true) end))
vim.health,capability.terminal_supported,raster.has_converter,vim.fn.executable=original_health,original_terminal,original_converter,original_executable
vim.ui.img=original_img
package.loaded.sprite=nil
print('health renderer prerequisites: ok')
