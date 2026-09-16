--[[

The MIT License (MIT)
Copyright (C) 2026 Flay Krunegan

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

]]

inv_manager = {
    S = core.get_translator("inv_manager"),
}

local S = inv_manager.S

core.register_privilege("inv_manager", {
    description = S("View and modify players' inventories"),
    give_to_singleplayer = false,
})

core.register_privilege("inv_viewer", {
    description = S("View players' inventories (read only)"),
    give_to_singleplayer = false,
})

local modpath = core.get_modpath("inv_manager")
for _, file in ipairs({
    "settings",
    "util",
    "storage",
    "sections",
    "snapshots",
    "session",
    "gui",
    "commands",
    "integration",
}) do
    dofile(modpath .. "/src/" .. file .. ".lua")
end
