vim.opt.runtimepath:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local calls = { available = 0, open = 0, discoveries = 0, order = {} }
local render_root
package.loaded["svgtree.render"] = {
	open = function(path)
		render_root = path
	end,
	close = function()
		render_root = nil
	end,
	root = function()
		return render_root
	end,
	snapshot = function()
		return { root = render_root, expanded = {}, widths = { terminal = 36, native = 280 } }
	end,
}
package.loaded["svgtree.capability"] = { detect = function() end }
package.loaded["svgtree.native"] = nil
package.loaded.sprite = nil
package.preload.sprite = function()
	return {
		available = function(callback)
			calls.available = calls.available + 1
			calls.discoveries = calls.discoveries + 1
			calls.order[#calls.order + 1] = "available"
			callback(nil, { features = { "owned-dock-v1", "virtual-list-v1", "svg-assets-v1", "dock-resize-v1" } })
			return function() end
		end,
		register_tokens = function(_, callback)
			calls.order[#calls.order + 1] = "tokens"
			callback(nil)
		end,
		on_resume = function()
			return function() end
		end,
		open = function(_, callback)
			calls.open = calls.open + 1
			calls.discoveries = calls.discoveries + 1
			calls.order[#calls.order + 1] = "open"
			callback({ code = "unsupported", message = "dock capability refused" })
			return function() end
		end,
	}
end

local tree = require("svgtree")
tree.setup({ renderer = "auto" })
tree.open(root)
assert(calls.open == 1, "native open is attempted directly")
assert(calls.discoveries == 1 and calls.available == 0, "open performs the single capability discovery")
assert(calls.order[1] == "tokens" and calls.order[2] == "open", "tokens register before open")
assert(tree.root() == root and render_root == root, "open refusal falls back to terminal Explorer")
tree.close()

package.loaded.sprite = nil
package.preload.sprite = function()
	return {
		available = function()
			error("available must not be required")
		end,
	}
end
tree.open(root)
assert(tree.root() == root and render_root == root, "missing open API falls back to terminal Explorer")
tree.close()

vim.fn.delete(root, "rf")
print("native open discovery: ok")
