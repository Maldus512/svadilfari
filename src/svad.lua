#!/usr/bin/env lua

local getTargets = function(ninjaFile)
    local output = assert(io.popen(string.format("ninja -f %s -t targets", ninjaFile)), "Could not run ninja!")
    if output == nil then
        return {}
    end
    local targetLines = {}
    local line = output:read()
    while line do
        local target = string.match(line, "^(%S+):")
        table.insert(targetLines, target)
        line = output:read()
    end

    local _, _, code = output:close()
    if code ~= 0 then
        print("Could not query ninja for targets!")
    end
    return targetLines
end

local printHelp = function(commands)
    print("Usage:")
    print("  svad.lua [command]")
    print("")
    print("COMMANDS")
    for name, command in pairs(commands) do
        if name ~= "ninja" then
            print(string.format("  %-15s%s", name, type(command) == "table" and command.description or "" or ""))
        end
    end
    if commands.ninja then
        local targets = getTargets(commands.ninja)
        print("")
        print(string.format("Ninja targets: %s", table.concat(targets, ", ")))
    end
end

local runWithOutput = function(command)
    local output = io.popen(command)
    if output ~= nil then
        local line = output:read()
        while line ~= nil do
            print(line)
            line = output:read()
        end
        local _, _, code = output:close()
        return code == 0
    else
        return false
    end
end

local main = function()
    ---@type ({commands : any[]} | boolean)
    local status, value = pcall(function() return require("build") end)

    if status then
        if type(value) == "table" then
            if #arg < 1 or arg[1] == "help" then
                print(
                    "Svaðilfari, tireless horse that (almost) built the walls of Asgard is now at our service to build some software - with the help of a mercenary from feudal Japan, apparently.")
                print("")
                printHelp(value)
            else
                for name, command in pairs(value) do
                    if name == arg[1] then
                        if type(command) == "string" then
                            runWithOutput(command)
                        elseif type(command) == "function" then
                            command(table.unpack(arg, 2))
                        else
                            command.action(table.unpack(arg, 2))
                        end
                        return
                    end
                end

                if value.ninja then
                    local targets = getTargets(value.ninja)
                    for _, target in ipairs(targets) do
                        if target == arg[1] then
                            runWithOutput(string.format("ninja -f %s %s", value.ninja, target))
                            return
                        end
                    end
                end

                print("Unrecognized command: " .. arg[1])
                print("")
                printHelp(value)
                os.exit(-1)
            end
        else
            print(string.format("build.lua should return a table of commands, found a %s instead!", type(value)))
        end
    else
        print("Could not open build.lua!")
        print(status, value)
    end
end


main()
