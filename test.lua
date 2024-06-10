local svad = require("src.svadilfari")

local buildConfig = svad.new {}
local gcc = buildConfig.addRule {
    name = "compileC",
    command = "gcc",
}

local ld = buildConfig.addRule {
    name = "linker",
    command = "ld",
}

buildConfig.addBuildPipe {
    gcc {
        input = "main.c",
        output = svad.toExtension("o"),
    },
    ld {
        output = "main",
    },
}

print(buildConfig.exportToString())
