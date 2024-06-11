---@diagnostic disable: redefined-local

---@alias BuildStepBuilder fun(args: {input:string, output : (string | fun(string): string), implicitDeps: table?, env:table}) : BuildStep
---@alias Rule { command: string, env: table? }
---@alias BuildStep { rule: string, input: string?, output: (string | fun(string): string), implicitDeps: table?, env: table? }
---@alias BuildCommand { command: string, input: string?, output: (string | fun(string): string), implicitDeps: table? }

---@class BuildConfiguration
---@field env table<string,string>
---@field rule fun(self: BuildConfiguration, rule: (string | {name: string, command: string, env:table?})): BuildStepBuilder
---@field buildStep fun(self: BuildConfiguration, buildStep: BuildStep): nil
---@field buildCommand fun(self: BuildConfiguration, buildCommand: BuildCommand): nil
---@field buildPipe fun(self: BuildConfiguration, buildSteps: BuildStep[]): nil
---@field getRule fun(self: BuildConfiguration, name: string): BuildStepBuilder
---@field toStringGenerator fun(self: BuildConfiguration): thread
---@field addCComponent fun(self: BuildConfiguration, args: {cc: string?, ld: string?, cflags: string?, ldflags: string?}): {cc:BuildStepBuilder, ld: BuildStepBuilder}


---@param extension string
---@return fun(string) string
local toExtension = function(extension)
    return function(input)
        return input:gsub("%.[^.]+$", "." .. extension)
    end
end

---@param path string
---@param extension string
---@param exclude string[] | nil
---@return string[]
local listFilesOfType = function(path, extension, exclude)
    exclude = exclude or {}
    local files = {}

    local dirname = function(path)
        return path:gsub("/[^/]*$", "")
    end

    local containsDirectory = function(array, directory)
        for _, element in ipairs(array) do
            if dirname(element) == dirname(directory) then
                return true
            end
        end
        return false
    end

    for file in io.popen("find " .. path .. " -name *." .. extension):lines() do
        if not containsDirectory(exclude, dirname(file)) then
            table.insert(files, file)
        end
    end

    return files
end

return {
    ---Creates a new instance of the build configuration
    ---@param args {buildFolder: string?, compiler: string?}
    ---@return BuildConfiguration
    newBuildConfiguration = function(args)
        local pwd = io.popen("pwd"):read()

        local privateSelf = {
            ---@type string
            buildFolder = string.format("%s/%s", pwd, args.buildFolder or ""),
            ---@type string
            compiler = args.compiler or "cc",
            ---@type table<string, Rule>
            rules = {},
            ---@type BuildStep[]
            buildSteps = {},
        }

        ---Join two filesystem paths
        ---@param ... string?[]
        ---@return string
        local join = function(...)
            local args = { ... }
            local result = ""
            for _, path in ipairs(args) do
                result = result .. "/" .. path
            end
            return result:gsub("/+", "/")
        end

        ---Get the path starting with base, do nothing if it's already the case
        ---@param base string
        ---@param path string?
        ---@return string?
        local getBasedPath = function(base, path)
            if path == nil then
                return nil
            elseif path:match("^" .. base) then
                return path
            else
                return join(base, path)
            end
        end

        local commandName = function(command)
            local simpleName = command:match("^%S+")
            if privateSelf.rules[simpleName] then
                return string.format([["%s"]], command)
            else
                return simpleName
            end
        end

        ---@type BuildConfiguration
        local buildConfig = {
            --[[
             Public fields
             ]]
            env = {},
            --[[
             Public methods
            ]]
            rule = function(self, rule)
                if type(rule) == "string" then
                    local name = commandName(rule)
                    if privateSelf.rules[name] ~= nil then
                        print("Warning: overriding rule named " .. name)
                    end
                    privateSelf.rules[name] = { command = rule }
                    return self:getRule(name)
                else
                    local name = rule.name or commandName(rule.command)
                    if privateSelf.rules[name] ~= nil then
                        print("Warning: overriding rule named " .. rule.name)
                    end
                    privateSelf.rules[name] = { command = rule.command, env = rule.env }
                    return self:getRule(name)
                end
            end,
            getRule = function(_, name)
                assert(privateSelf.rules[name], string.format("No rule with name %s!", name))
                return function(args)
                    local buildStep = { rule = name }
                    for k, v in pairs(args) do
                        buildStep[k] = v
                    end
                    return buildStep
                end
            end,
            buildStep = function(self, buildStep)
                self:buildPipe { buildStep }
            end,
            buildCommand = function(self, buildCommand)
                local name = commandName(buildCommand.command)

                local rule = self:rule {
                    name = name,
                    command = buildCommand.command,
                }

                return rule {
                    input = buildCommand.input,
                    output = buildCommand.output,
                    implicitDeps = buildCommand.implicitDeps,
                }
            end,
            buildPipe = function(_, buildSteps)
                local previousInput = nil

                for _, buildStep in ipairs(buildSteps) do
                    if buildStep.input == nil then
                        buildStep.input = previousInput
                    end

                    local output = buildStep.output
                    if type(output) == "function" then
                        output = output(buildStep.input)
                    end

                    local input = getBasedPath(io.popen("pwd"):read(), buildStep.input)
                    output = getBasedPath(privateSelf.buildFolder, output) --[[@as string]]

                    table.insert(privateSelf.buildSteps, {
                        rule = buildStep.rule,
                        input = input,
                        output = output,
                        implicitDeps = buildStep.implicitDeps,
                        env = buildStep.env,
                    })

                    previousInput = output
                end

                return previousInput --[[@as string]]
            end,
            toStringGenerator = function(self)
                return coroutine.create(function()
                    local environmentToString = function(indent, environment)
                        for key, value in pairs(environment) do
                            coroutine.yield(string.format("%s%s = %s\n", indent, key, value))
                        end
                    end

                    environmentToString("", self.env)
                    coroutine.yield("\n")

                    for name, rule in pairs(privateSelf.rules) do
                        coroutine.yield(string.format("rule %s\n    command = %s\n", name, rule.command))
                        if rule.env ~= nil then
                            environmentToString("    ", rule.env)
                        end
                        coroutine.yield("\n")
                    end

                    for _, buildStep in ipairs(privateSelf.buildSteps) do
                        local build = string.format("build %s: %s %s", buildStep.output, buildStep.rule, buildStep.input)
                        if buildStep.implicitDeps ~= nil then
                            build = build .. " |"
                            for _, dep in ipairs(buildStep.implicitDeps) do
                                build = build .. " " .. dep
                            end
                        end
                        coroutine.yield(build .. "\n")

                        if buildStep.env ~= nil then
                            environmentToString("    ", buildStep.env)
                        end
                        coroutine.yield("\n")
                    end
                end)
            end,
            -- Utility methods
            addCComponent = function(self, args)
                if args.cc == nil and privateSelf.rules.cc == nil then
                    args.cc = privateSelf.compiler
                end

                if args.cc then
                    self:rule {
                        name = "cc",
                        command = string.format("%s -MD -MF $out.d $cflags -c $in -o $out", args.cc),
                        env = { deps = "gcc", depfile = "$out.d" },
                    }
                end

                if args.ld == nil and privateSelf.rules.ld == nil then
                    self:rule {
                        name = "ld",
                        command = string.format("%s $ldflags $in -o $out", privateSelf.compiler),
                    }
                elseif args.ld then
                    self:rule {
                        name = "ld",
                        command = string.format("%s $ldflags $in -o $out", args.ld)
                    }
                end

                self.env.cflags = args.cflags
                self.env.ldflags = args.ldflags

                local cc = self:getRule("cc")
                local ld = self:getRule("ld")

                return { cc = cc, ld = ld }
            end,
        }

        return buildConfig
    end,
    toExtension = toExtension,
    listFilesOfType = listFilesOfType,
}
