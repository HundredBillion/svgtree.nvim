vim.opt.runtimepath:prepend(vim.fn.getcwd())
local original_cwd = vim.fn.getcwd()
local function same_dir(a, b)
	return vim.uv.fs_realpath(a) == vim.uv.fs_realpath(b)
end
local first, second = vim.fn.tempname(), vim.fn.tempname()
vim.fn.mkdir(first, "p")
vim.fn.mkdir(second, "p")
local calls, pending, warnings = {}, {}, {}
local available_calls = 0
local root, kind, width = nil, nil, nil
local render = {
	open = function(path, saved)
		saved = require("svgtree.state").resolve(path, saved)
		root = path
		kind = "terminal"
		width = saved.widths.terminal
		calls[#calls + 1] = "terminal"
	end,
	close = function()
		root = nil
		kind = nil
		calls[#calls + 1] = "terminal-close"
	end,
	root = function()
		return root
	end,
	snapshot = function()
		return { root = root, expanded = {}, widths = { terminal = width or 36, native = 280 } }
	end,
}
local Native = {
	open = function(path, saved, cb)
		local item = { path = path, saved = saved, callbacks = cb, cancelled = false }
		pending[#pending + 1] = item
		return function()
			item.cancelled = true
			calls[#calls + 1] = "native-close"
		end
	end,
}
package.loaded["svgtree.render"] = render
package.loaded["svgtree.native"] = Native
package.preload.sprite = function()
	return {
		available = function()
			available_calls = available_calls + 1
			error("available preflight must not run")
		end,
		open = function()
			return function() end
		end,
		register_tokens = function(_, callback)
			callback(nil)
		end,
		on_resume = function()
			return function() end
		end,
	}
end
package.loaded.sprite = nil
local notify = vim.notify
vim.notify = function(msg)
	warnings[#warnings + 1] = msg
end
local tree = require("svgtree")
tree.setup({ renderer = "auto" })
assert(
	package.loaded["svgtree.raster"] == nil and package.loaded["svgtree.capability"] == nil,
	"setup must not load raster or probe Kitty"
)
tree.open(first)
assert(#pending == 1 and #calls == 0 and tree.root() == first, "native initialization starts directly")
pending[1].callbacks.failed({ code = "timeout", message = "timed out" })
assert(#calls == 1 and calls[1] == "terminal" and #warnings == 0, "timeout falls back once")
pending[1].callbacks.failed({ code = "timeout", message = "again" })
assert(#calls == 1, "late failure must not open another tree")
tree.close()
tree.setup({ renderer = "terminal" })
tree.open(first)
assert(calls[#calls] == "terminal", "terminal bypasses Sprite")
tree.close()
tree.setup({ renderer = "sprite" })
tree.open(first)
pending[#pending].callbacks.failed({ code = "refused", message = "dock occupied" })
assert(
	calls[#calls] == "terminal" and #warnings == 1 and warnings[1]:find("dock occupied", 1, true),
	"forced failure warns and falls back"
)
tree.close()
tree.setup({ renderer = "auto" })
tree.open(first)
local stale = pending[#pending]
tree.toggle()
assert(stale.cancelled and tree.root() == nil, "toggle cancels pending native open")
stale.callbacks.ready({
	close = function()
		calls[#calls + 1] = "stale-close"
	end,
})
assert(tree.root() == nil and stale.cancelled, "late ready cannot reopen after toggle")
tree.open(first)
local old = pending[#pending]
tree.open(second)
assert(old.cancelled and tree.root() == second, "root switch cancels opening native")
old.callbacks.ready({
	close = function()
		calls[#calls + 1] = "stale-close"
	end,
})
assert(calls[#calls] == "stale-close" and tree.root() == second, "late ready closes orphan")
local current = pending[#pending]
local snapshot = {
	root = second,
	expanded = { [second .. "/dir"] = true },
	selected = second .. "/dir",
	widths = {
		native = 300,
		terminal = 42,
	},
}
local view = {
	snapshot = function()
		return snapshot
	end,
	close = function()
		calls[#calls + 1] = "native-close"
	end,
}
current.callbacks.ready(view)
assert(tree.root() == second)
current.callbacks.failed({ code = "unavailable", message = "connection lost" })
assert(tree.root() == second and calls[#calls] == "terminal" and width == 42, "ready failure restores terminal state")
local before = #calls
current.callbacks.failed({ code = "unavailable", message = "again" })
assert(#calls == before, "failure must only fall back once")
tree.close()
tree.open(second)
local navigation = pending[#pending]
local native_focuses = 0
local navigation_view = {
	snapshot = function()
		return snapshot
	end,
	close = function()
		calls[#calls + 1] = "native-close"
	end,
	focus = function()
		native_focuses = native_focuses + 1
	end,
}
navigation.callbacks.ready(navigation_view)
assert(tree.focus("left") and native_focuses == 1, "focus enters the native left sidebar")
assert(not tree.focus("right") and native_focuses == 1, "opposite direction falls through to normal window navigation")
navigation.callbacks.root(first)
assert(tree.root() == first and calls[#calls] == "native-close", "native root navigation replaces the active tree")
assert(same_dir(vim.fn.getcwd(), first), "native root navigation changes the editor directory")
assert(pending[#pending].path == first, "native root navigation opens the requested root directly")
tree.close()
package.loaded.sprite = nil
package.preload.sprite = function()
	error("module missing")
end
tree.open(first)
assert(
	tree.root() == first and calls[#calls] == "terminal" and #warnings == 1,
	"missing Sprite module quietly falls back"
)
tree.close()
assert(available_calls == 0, "dispatch never performs an available preflight")
local clears = 0
package.loaded["svgtree.native_view"] = {
	clear_cache = function()
		clears = clears + 1
	end,
}
tree.setup({ renderer = "auto" })
assert(clears == 1, "setup invalidates cached SVG bytes after pack replacement")
vim.notify = notify
vim.api.nvim_set_current_dir(original_cwd)
vim.fn.delete(first, "rf")
vim.fn.delete(second, "rf")
print("native dispatch ok")
