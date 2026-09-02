-- Static checks on the .toc manifests. Run from the addon root:
--     lua tests/check_toc.lua
-- Guards the failure that made this addon dead on arrival: a library that lives
-- in the repo but is not referenced by any .toc, and so is never loaded.

local TOCS = {
    "RaapWhistle.toc",
    "RaapWhistle_Mainline.toc",
    "RaapWhistle_Vanilla.toc",
    "RaapWhistle_TBC.toc",
    "RaapWhistle_Wrath.toc",
}

local errors = {}

local function fail(fmt, ...)
    errors[#errors + 1] = string.format(fmt, ...)
end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the ordered list of files a .toc asks the client to load, plus the
-- directives it declares.
local function parse(toc)
    local files, directives = {}, {}
    local fh = io.open(toc, "r")
    if not fh then
        fail("%s: missing", toc)
        return nil
    end
    for line in fh:lines() do
        line = trim(line):gsub("^\239\187\191", "")  -- tolerate a UTF-8 BOM
        local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
        if key then
            directives[trim(key)] = trim(value)
        elseif line ~= "" and line:sub(1, 1) ~= "#" then
            files[#files + 1] = line
        end
    end
    fh:close()
    return files, directives
end

local reference, referenceToc

for _, toc in ipairs(TOCS) do
    local files, directives = parse(toc)
    if files then
        for _, entry in ipairs(files) do
            -- .toc files use Windows separators; the repo is checked out with
            -- forward slashes everywhere else.
            local path = entry:gsub("\\", "/")
            if not exists(path) then
                fail("%s: lists %s, which does not exist", toc, entry)
            end
        end

        local listed = false
        for _, entry in ipairs(files) do
            if entry:gsub("\\", "/") == "RaapWhistle.lua" then listed = true end
        end
        if not listed then fail("%s: never loads RaapWhistle.lua", toc) end

        for _, key in ipairs({ "Interface", "Title", "Version", "SavedVariables" }) do
            if not directives[key] or directives[key] == "" then
                fail("%s: missing ## %s", toc, key)
            end
        end

        if directives.SavedVariables and directives.SavedVariables ~= "RaapWhistleDB" then
            fail("%s: ## SavedVariables is %q, expected RaapWhistleDB",
                toc, directives.SavedVariables)
        end

        for value in (directives.Interface or ""):gmatch("[^,%s]+") do
            if not value:match("^%d%d%d%d%d+$") then
                fail("%s: %q is not a valid interface number", toc, value)
            end
        end

        -- Every flavor must load the same files in the same order, or a fix
        -- lands on one client and not the others.
        if not reference then
            reference, referenceToc = files, toc
        else
            local same = #files == #reference
            if same then
                for i = 1, #files do
                    if files[i] ~= reference[i] then same = false end
                end
            end
            if not same then
                fail("%s: load order differs from %s", toc, referenceToc)
            end
        end
    end
end

-- Best effort: catch a .toc that was added to the repo but not to TOCS above.
-- Skipped on Windows, where io.popen goes through cmd.exe and has no `ls`; CI
-- runs on Linux, so drift is still caught there.
local isPosix = package.config:sub(1, 1) == "/"
local ok, pipe = false, nil
if isPosix then ok, pipe = pcall(io.popen, "ls -1 *.toc 2>/dev/null") end
if ok and pipe then
    for name in pipe:lines() do
        name = trim(name)
        local known = false
        for _, toc in ipairs(TOCS) do
            if toc == name then known = true end
        end
        if name ~= "" and not known then
            fail("%s exists but is not covered by tests/check_toc.lua", name)
        end
    end
    pipe:close()
end

if #errors > 0 then
    print("")
    print("toc check FAILED")
    for _, e in ipairs(errors) do print("  " .. e) end
    print("")
    os.exit(1)
end

print(string.format("toc check ok (%d manifests)", #TOCS))
