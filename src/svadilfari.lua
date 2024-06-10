---@diagnostic disable: redefined-local

---@alias RuleBuildStep fun(args: {input:string, env:table})
---@alias Rule { command: string, env: table? }
---@alias BuildStep { rule: string, input: string?, output: (string | fun(string): string), implicitDependencies: table?, env: table? }

---@class BuildConfiguration
---@field addRule fun(rule: {name: string, command: string, env:table?}): RuleBuildStep
---@field addBuildStep fun(buildStep: BuildStep): nil
---@field addBuildPipe fun(buildSteps: BuildStep[]): nil
---@field exportToString fun(): string


---Creates a new instance of the build configuration
---@param args {buildFolder: string?, toolchain: string?}
---@return BuildConfiguration
local new = function(args)
    local self = {
        buildFolder = args.buildFolder or io.popen("pwd"):read(),
        toolchain = args.toolchain or "",
        ---@type table<string, Rule>
        rules = {},
        ---@type BuildStep[]
        buildSteps = {},
    }

    local environmentToString = function(environment)
        local result = ""
        for key, value in pairs(environment) do
            result = result .. string.format("    {} = {}\n", key, value)
        end
        return result
    end

    local addBuildStepWithRelocate = function(relocate, buildStep)
        local output = buildStep.output
        if type(output) == "function" then
            output = output(buildStep.input)
        end
        if relocate then
            output = self.buildFolder .. "/" .. output
        end

        output = io.popen("realpath " .. output):read()

        table.insert(self.buildSteps, {
            rule = buildStep.rule,
            input = buildStep.input,
            output = output,
            implicitDependencies = buildStep.implicitDependencies,
            env = buildStep.env,
        })

        return output
    end

    local addRule = function(rule)
        assert(self.rules[rule.name] == nil, "There is already a rule with name " .. rule.name)
        self.rules[rule.name] = { command = rule.command, env = rule.env }
        return function(args)
            local buildStep = { rule = rule.name }
            for k, v in pairs(args) do
                buildStep[k] = v
            end
            return buildStep
        end
    end

    local addBuildPipe = function(buildSteps)
        local input = nil
        local first = true

        for _, buildStep in ipairs(buildSteps) do
            if buildStep.input == nil then
                buildStep.input = input
            end

            input = addBuildStepWithRelocate(first, buildStep)
            first = false
        end

        return input --[[@as string]]
    end

    local exportToString = function()
        local result = ""

        for name, rule in pairs(self.rules) do
            result = result .. string.format("rule %s\n    command = %s\n", name, rule.command)
            if rule.env ~= nil then
                result = result .. environmentToString(rule.env)
            end
            result = result .. "\n"
        end

        for _, buildStep in ipairs(self.buildSteps) do
            local build = string.format("build %s: %s %s", buildStep.output, buildStep.rule, buildStep.input)
            if buildStep.implicitDependencies ~= nil then
                build = build .. " |"
                for _, dep in ipairs(buildStep.implicitDependencies) do
                    build = build .. " " .. dep
                end
            end
            result = result .. build .. "\n"

            if buildStep.env ~= nil then
                result = result .. environmentToString(buildStep.env)
            end
            result = result .. "\n"
        end

        return result
    end

    ---@type BuildConfiguration
    return {
        addRule = addRule,
        addBuildPipe = addBuildPipe,
        addBuildStep = function(buildStep)
            addBuildPipe { buildStep }
        end,
        exportToString = exportToString,
    }
end

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
    new = new,
    toExtension = toExtension,
    listFilesOfType = listFilesOfType,
}
