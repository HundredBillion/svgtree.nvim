local Pack = require('svgtree.pack')
local M = {}
local asset_cache = {}
function M.clear_cache() asset_cache = {} end
local tokens = {
  {'background','#181818'}, {'foreground','#cccccc'}, {'hover','#2a2d2e'},
  {'selection','#04395e'}, {'inactiveSelection','#37373d'},
  {'selectionForeground','#ffffff'}, {'focus','#0078d4'},
  {'guide','#585858'}, {'border','#2b2b2b'}, {'scrollbar','#3f3f3f'},
}
function M.tokens()
  local result={}
  for _, pair in ipairs(tokens) do result[#result+1]={name='svgtree.'..pair[1],default=pair[2],description='Explorer '..pair[1]} end
  return result
end
function M.description(_,root,collapsed,side)
  local name=vim.fn.fnamemodify(root,':t'):upper()
  local colors={}
  local roles={selection='selected',inactiveSelection='inactive_selected',selectionForeground='selected_foreground'}
  for _, pair in ipairs(tokens) do colors[roles[pair[1]] or pair[1]]='svgtree.'..pair[1] end
  return {version=1,root={kind='virtual_list',border_side=side=='right' and 'left' or 'right',row_height=22,font_size=13,
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
    local parent=vim.fn.fnamemodify(row.path,':h:t')
    local icon=Pack.resolve(pack.theme,name,row.kind,row.expanded,{parent=parent})
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
  ['svgtree-chevron-right']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="#cccccc" transform="translate(2 0)" d="M6.14601 3.14579C5.95101 3.34079 5.95101 3.65779 6.14601 3.85279L10.292 7.99879L6.14601 12.1448C5.95101 12.3398 5.95101 12.6568 6.14601 12.8518C6.34101 13.0468 6.65801 13.0468 6.85301 12.8518L11.353 8.35179C11.548 8.15679 11.548 7.83979 11.353 7.64478L6.85301 3.14479C6.65801 2.94979 6.34101 2.95079 6.14601 3.14579Z"/></svg>',
  ['svgtree-chevron-down']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="#cccccc" transform="translate(3 0)" d="M3.14598 5.85423L7.64598 10.3542C7.84098 10.5492 8.15798 10.5492 8.35298 10.3542L12.853 5.85423C13.048 5.65923 13.048 5.34223 12.853 5.14723C12.658 4.95223 12.341 4.95223 12.146 5.14723L7.99998 9.29323L3.85398 5.14723C3.65898 4.95223 3.34198 4.95223 3.14698 5.14723C2.95198 5.34223 2.95098 5.65923 3.14598 5.85423Z"/></svg>',
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
