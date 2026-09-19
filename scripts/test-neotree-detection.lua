vim.opt.runtimepath:prepend(vim.fn.getcwd())
local tree=require('svgtree')
tree.setup({renderer='auto',warm=true})
assert(package.loaded['svgtree.capability']==nil and package.loaded['svgtree.raster']==nil,'native setup stays lazy')
local detects, warms, attached=0,0,0
local resolved
local supported=false
package.loaded['svgtree.capability']={detect=function() detects=detects+1 end,
  supported_cached=function() return supported end,
  on_resolved=function(cb) resolved=cb end}
package.loaded['svgtree.raster']={has_converter=function() return true end,warm=function() warms=warms+1 end}
package.loaded['svgtree.engine']={attach=function() attached=attached+1;return {schedule=function() end,detach=function() end} end}
local adapter=require('svgtree.adapters.neotree')
local buf=vim.api.nvim_create_buf(false,true)
local win=vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win,buf)
local state={winid=win,tree={get_node=function() return nil end}}
adapter.on_render({state=state})
assert(detects>0,'adapter-only rendering starts capability detection')
assert(vim.wait(100,function() return warms==1 end),'adapter request honors warm=true once')
assert(type(resolved)=='function','adapter waits for detection result')
supported=true
resolved()
assert(attached==1,'adapter attaches after graphics result without another host render')
adapter.on_render({state=state})
assert(warms==1,'warm is not repeated on render')
print('neo-tree detection ok')
