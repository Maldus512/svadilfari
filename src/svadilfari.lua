---@diagnostic disable: redefined-local

---@alias BuildStepFactory fun(args: {input: (string|string[]), target : (string | fun(string): string), alias: string?, dependencies: table?, env:table?}) : BuildStep
---@alias Rule { command: string, env: table? }
---@alias BuildStep { rule: string, input: (string|string[])?, target: (string | fun(string): string), alias: string?, dependencies: table?, env: table? }

---@class BuildConfiguration
---@field env table<string,string>
---@field rule fun(self: BuildConfiguration, rule: {name: string, command: string, env:table?}): BuildStepFactory
---@field command fun(self: BuildConfiguration, command: string): BuildStepFactory
---@field step fun(self: BuildConfiguration, buildStep: BuildStep): string
---@field alias fun(self: BuildConfiguration, name: string, target: string)
---@field run fun(self: BuildConfiguration, args: {name: string, input: (string|string[])?, dependencies: string?, command: string})
---@field pipe fun(self: BuildConfiguration, buildSteps: BuildStep[]): string[]
---@field defaults fun(self: BuildConfiguration, targets: string[] | string)
---@field getRule fun(self: BuildConfiguration, name: string): BuildStepFactory
---@field toStringGenerator fun(self: BuildConfiguration): thread
---@field export fun(self: BuildConfiguration, path: string)
---@field addCComponent fun(self: BuildConfiguration, args: {sourceDirs:string?, app: string?, cc: string?, ld: string?, includes: string[]?, defines: string[]?, cflags: string?, ldflags: string?}): {cc: BuildStepFactory, ld: BuildStepFactory, object: string[], binary: string}


---@param extension string
---@return fun(string) string
local toExtension = function(extension)
    return function(input)
        return input:gsub("%.[^.]+$", "." .. extension)
    end
end

---@generic T : any?
---@param element T
---@return T[]
local toList = function(element)
    if element == nil then
        return {}
    elseif type(element) == "table" then
        return element
    else
        return { element }
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
            ---@type string[]
            defaults = {},
        }

        local getInput = function(input)
            if type(input) == "table" then
                return table.concat(args.input --[[@as string[] ]], " ")
            elseif type(input) == "string" then
                return input
            else
                return ""
            end
        end

        ---Join two filesystem paths
        ---@param ... string?[]
        ---@return string
        local join = function(...)
            local args = { ... }
            local result = ""
            for _, path in ipairs(args) do
                result = result .. "/" .. path
            end
            result = string.gsub(result, "/+", "/")
            return result
        end

        local getBasedPath
        ---Get the path starting with base, do nothing if it's already the case
        ---@param base string
        ---@param path (string|string[])?
        ---@return string?
        getBasedPath = function(base, path)
            if path == nil then
                return nil
            elseif type(path) == "table" then
                local result = {}
                for _, v in ipairs(path) do
                    local basedPath = getBasedPath(base, v)
                    table.insert(result, basedPath)
                end
                return table.concat(result, " ")
            else
                local start, _ = path:find(base, 1, true)
                if start == 1 then
                    return path
                else
                    return join(base, path)
                end
            end
        end

        local commandName = function(command)
            local simpleName = command:match("^%S+")
            if privateSelf.rules[simpleName] then
                return command:gsub("[%s%p]", "_")
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
                if privateSelf.rules[rule.name] ~= nil then
                    print("Warning: overriding rule named " .. rule.name)
                end
                privateSelf.rules[rule.name] = { command = rule.command, env = rule.env }
                return self:getRule(rule.name)
            end,
            command = function(self, command)
                return self:rule {
                    name = commandName(command),
                    command = command,
                }
            end,
            getRule = function(_, name)
                assert(privateSelf.rules[name], string.format("No rule with name %s!", name))
                return function(args)
                    assert(args.target, "Unspecified target!")
                    local buildStep = { rule = name }
                    for k, v in pairs(args) do
                        buildStep[k] = v
                    end
                    return buildStep
                end
            end,
            step = function(self, buildStep)
                return (self:pipe { buildStep })[1]
            end,
            alias = function(_, name, other)
                table.insert(privateSelf.buildSteps, {
                    rule = "phony",
                    input = other,
                    target = name,
                })
            end,
            run = function(self, args)
                assert(args.name, "Run target must have a (humanly readable) name!")
                assert(args.command, "Run target must do something!")

                self:rule {
                    name = args.name,
                    command = args.command
                }

                table.insert(privateSelf.buildSteps, {
                    rule = args.name,
                    input = getInput(args.input),
                    target = args.name,
                    dependencies = args.dependencies,
                })
            end,
            pipe = function(self, buildSteps)
                local previousInput = nil
                local outputsList = {}

                for _, buildStep in ipairs(buildSteps) do
                    if buildStep.input == nil then
                        buildStep.input = previousInput
                    end

                    local target = buildStep.target --[[ @as string ]]
                    if type(buildStep.target) == "function" then
                        target = buildStep.target(buildStep.input)
                    end

                    local input = getBasedPath(io.popen("pwd"):read(), buildStep.input)
                    target = getBasedPath(privateSelf.buildFolder, target) --[[@as string]]

                    table.insert(privateSelf.buildSteps, {
                        rule = buildStep.rule,
                        input = input,
                        target = target,
                        dependencies = buildStep.dependencies,
                        env = buildStep.env,
                    })

                    if buildStep.alias then
                        self:alias(buildStep.alias, target)
                    end

                    previousInput = target
                    table.insert(outputsList, target)
                end

                return outputsList
            end,
            defaults = function(_, targets)
                if type(targets) == "table" then
                    for _, v in ipairs(targets) do
                        table.insert(privateSelf.defaults, v)
                    end
                else
                    table.insert(privateSelf.defaults, targets)
                end
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
                        local build = string.format("build %s: %s %s", buildStep.target, buildStep.rule, buildStep.input)
                        if buildStep.dependencies ~= nil then
                            build = build .. " |"
                            for _, dep in ipairs(buildStep.dependencies) do
                                build = build .. " " .. dep
                            end
                        end
                        coroutine.yield(build .. "\n")

                        if buildStep.env ~= nil then
                            environmentToString("    ", buildStep.env)
                        end
                        coroutine.yield("\n")
                    end

                    if #privateSelf.defaults > 0 then
                        coroutine.yield("default " .. table.concat(privateSelf.defaults, " "))
                    end

                    coroutine.yield("\n")
                end)
            end,
            export = function(self, path)
                local file = io.open(path, "w")
                if file == nil then
                    print(string.format("Could not create %s!", path))
                else
                    local generator = self:toStringGenerator()

                    while coroutine.status(generator) ~= "dead" do
                        local _, value = coroutine.resume(generator)
                        if value ~= nil then
                            file:write(value)
                        end
                    end

                    file:close()
                end
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

                self.env.cflags = args.cflags or ""
                self.env.ldflags = args.ldflags or ""

                local includes = toList(args.includes)
                for _, include in ipairs(includes) do
                    self.env.cflags = self.env.cflags .. " -I" .. include
                end

                local defines = toList(args.defines)
                for _, define in ipairs(defines) do
                    self.env.cflags = self.env.cflags .. " -D" .. define
                end


                local cc = self:getRule("cc")
                local ld = self:getRule("ld")

                local compileC = function(path)
                    return self:step((cc {
                        input = path,
                        target = toExtension("o")
                    }))
                end
                local objects = {}

                local sourceDirs = toList(args.sourceDirs)

                for _, sourceDir in ipairs(sourceDirs) do
                    for _, source in pairs(listFilesOfType(sourceDir, "c")) do
                        local object = compileC(source)
                        table.insert(objects, object)
                    end
                end

                local binary = nil
                if args.app and #objects > 0 then
                    binary = self:step((ld {
                        input = objects,
                        target = args.app,
                    }))
                end

                return { cc = cc, ld = ld, objects = objects, binary = binary }
            end,
        }

        return buildConfig
    end,
    toExtension = toExtension,
    listFilesOfType = listFilesOfType,
}
