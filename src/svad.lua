local printHelp = function(commands)
    print("Usage:")
    print("  svad.lua [command]")
    print("")
    print("COMMANDS")
    for _, command in pairs(commands) do
        print(string.format("  %-15s%s", command.name, command.description))
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
    local configuration, error = pcall(function() require("build") end)

    if configuration then
        if #arg < 1 or arg[1] == "help" then
            print(
                "Svaðilfari, tireless horse that (almost) built the walls of Asgard is now at our service to build some software - with the help of a mercenary from feudal Japan, apparently.")
            print("")
            printHelp()
        else
            for _, command in pairs(configuration.commands) do
                if command.name == arg[1] then
                    if type(command.action) == "function" then
                        command.action(table.unpack(arg, 2))
                    else
                        runWithOutput(command.action)
                    end
                    return
                end
            end

            print("Unrecognized command: " .. arg[1])
            print("")
            printHelp()
        end
    else
        print("build.lua not found!")
        print(error)
    end
end


main()
