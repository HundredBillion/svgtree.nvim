local Pack = require('svgtree.pack')
local M = {}
local asset_cache = {}
function M.clear_cache() asset_cache = {} end
local tokens = {
  {'background','#181818'}, {'foreground','#cccccc'}, {'hover','#2a2d2e'},
  {'selection','#04395e'}, {'inactiveSelection','#37373d'},
  {'selectionForeground','#ffffff'}, {'focus','#0078d4'},
  {'guide','#585858'}, {'border','#181818'}, {'scrollbar','#3f3f3f'},
}
function M.tokens()
  local result={}
  for _, pair in ipairs(tokens) do result[#result+1]={name='svgtree.'..pair[1],default=pair[2],description='Explorer '..pair[1]} end
  return result
end
function M.description(_,root,collapsed)
  local name=vim.fn.fnamemodify(root,':t'):upper()
  local colors={}
  local roles={selection='selected',inactiveSelection='inactive_selected',selectionForeground='selected_foreground'}
  for _, pair in ipairs(tokens) do colors[roles[pair[1]] or pair[1]]='svgtree.'..pair[1] end
  return {version=1,root={kind='virtual_list',row_height=22,font_size=13,
    font_family='Adwaita Sans',icon_size=16,icon_gap=6,left_padding=8,right_padding=8,
    scrollbar_width=10,guide_visibility='hover',inactive_guide_opacity=0.4,
    scrollbar_opacity=0.4,scrollbar_hover_opacity=0.7,scrollbar_active_opacity=0.4,
    heading={text='EXPLORER',height=35,font_size=11,font_weight='normal',left_padding=20},
    section={text=name,height=22,font_size=11,font_weight='bold',left_padding=0,icon_gap=4,icon=collapsed and 'svgtree-chevron-right' or 'svgtree-chevron-down',action='root-toggle'},
    colors=vim.tbl_extend('force',colors,{inactive_guide='svgtree.guide',scrollbar='#797979',scrollbar_hover='#646464',scrollbar_active='#bfbfbf'})}}
end
function M.rows(model,pack)
  local rows,ids={}, {['svgtree-chevron-down']=true,['svgtree-chevron-right']=true}
  local ancestors={}
  for _, row in ipairs(model) do
    local name=vim.fn.fnamemodify(row.path,':t')
    local icon=Pack.resolve(pack.theme,name,row.kind,row.expanded)
    if icon then ids[icon]=true end
    local leading=row.kind=='dir' and (row.expanded and 'svgtree-chevron-down' or 'svgtree-chevron-right') or 'svgtree-transparent'
    ids[leading]=true
    local guides={}
    for depth=0,math.min(row.depth-1,63) do
      local ancestor=ancestors[depth+1]
      if ancestor then guides[#guides+1]={offset=8+depth*8,id=ancestor} end
    end
    rows[#rows+1]={id=row.id,text=row.text,indent=math.min(row.depth*8,16384),icon=icon,leading=leading,guides=guides}
    ancestors[row.depth+1]=row.kind=='dir' and row.id or nil
    for depth=row.depth+2,#ancestors do ancestors[depth]=nil end
  end
  return rows,ids
end
function M.active_guides(rows,selected)
  local result,groups={},{}
  for _,row in ipairs(rows or {}) do
    for _,guide in ipairs(row.guides) do groups[guide.id]=true end
  end
  for _,row in ipairs(rows or {}) do
    if row.id==selected then
      for _,guide in ipairs(row.guides) do result[#result+1]=guide.id end
      if groups[selected] and #result<64 then result[#result+1]=selected end
      break
    end
  end
  return result
end
local builtin={
  ['svgtree-chevron-right']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="none" stroke="#cccccc" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="m6 4 4 4-4 4"/></svg>',
  ['svgtree-chevron-down']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="none" stroke="#cccccc" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="m4 6 4 4 4-4"/></svg>',
  ['svgtree-transparent']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"/>',
}
function M.assets(pack,ids)
  local result={}
  for id in pairs(ids) do
    local svg=builtin[id]
    if not svg then
      local path=Pack.icon_svg(pack.theme,pack.dir,id)
      local key=pack.dir .. '\0' .. id .. '\0' .. (path or '')
      local cached=asset_cache[key]
      if cached==nil then
        svg=false
        if path and vim.fn.filereadable(path)==1 then
          local ok,lines=pcall(vim.fn.readfile,path)
          if ok then
            local source=table.concat(lines,'\n'):gsub('^%s*<%?xml.-%?>%s*',''):gsub('^%s*<!%-%-.-%-%->%s*','')
            if source:match('^%s*<svg[%s>]') and (source:match('</svg>%s*$') or source:match('/>%s*$')) then svg=source end
          end
        end
        asset_cache[key]=svg
      else svg=cached end
    end
    if svg then result[id]=svg end
  end
  return result
end

return M
