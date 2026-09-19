local Pack = require('svgtree.pack')
local M = {}
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
    heading={text='EXPLORER',height=35,font_size=11,font_weight='normal',left_padding=20},
    section={text=name,height=22,font_size=11,font_weight='bold',left_padding=0,icon_gap=4,icon=collapsed and 'svgtree-chevron-right' or 'svgtree-chevron-down',action='root-toggle'},
    colors=colors}}
end
function M.rows(model,pack)
  local rows,ids={}, {['svgtree-chevron-down']=true,['svgtree-chevron-right']=true}
  for _, row in ipairs(model) do
    local name=vim.fn.fnamemodify(row.path,':t')
    local icon=Pack.resolve(pack.theme,name,row.kind,row.expanded)
    if icon then ids[icon]=true end
    local leading=row.kind=='dir' and (row.expanded and 'svgtree-chevron-down' or 'svgtree-chevron-right') or 'svgtree-transparent'
    ids[leading]=true
    local guides={}
    for depth=0,math.min(row.depth-1,63) do guides[#guides+1]=8+depth*8 end
    rows[#rows+1]={id=row.id,text=row.text,indent=math.min(row.depth*8,16384),icon=icon,leading=leading,guides=guides}
  end
  return rows,ids
end
local builtin={
  ['svgtree-chevron-right']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="#cccccc" d="m6 4 4 4-4 4z"/></svg>',
  ['svgtree-chevron-down']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path fill="#cccccc" d="m4 6 4 4 4-4z"/></svg>',
  ['svgtree-transparent']='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"/>',
}
function M.assets(pack,ids)
  local result={}
  for id in pairs(ids) do
    local svg=builtin[id]
    if not svg then
      local path=Pack.icon_svg(pack.theme,pack.dir,id)
      if path and vim.fn.filereadable(path)==1 then
        local ok,lines=pcall(vim.fn.readfile,path)
        if ok then
          svg=table.concat(lines,'\n'):gsub('^%s*<%?xml.-%?>%s*',''):gsub('^%s*<!%-%-.-%-%->%s*','')
          if not svg:match('^%s*<svg[%s>]') or not (svg:match('</svg>%s*$') or svg:match('/>%s*$')) then svg=nil end
        end
      end
    end
    if svg then result[id]=svg end
  end
  return result
end
return M
