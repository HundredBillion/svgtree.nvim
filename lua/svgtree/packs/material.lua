-- Material Icon Theme pack for svgtree.
--
-- Pairs the generated resolver (material_map.lua) with the on-disk icon pack.
-- The 1245 SVGs are NOT bundled in this repo (size + licensing); install them
-- once from the published `material-icon-theme` npm package into `pack` below.
-- See scripts/install-material.sh.
--
-- Usage:
--   local mat = require("svgtree.packs.material")
--   require("svgtree").setup({ pack = mat.pack, icon_map = mat })

local map = require('svgtree.packs.material_map')

return vim.tbl_extend('force', map, {
  -- Where the SVGs live. Override if you installed them elsewhere.
  pack = vim.fn.expand('~/.local/share/svgtree/material'),
})
