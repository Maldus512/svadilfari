local svad = require("src.svadilfari")

local exportToString = function(build)
    local generator = build:toStringGenerator()
    local result = ""

    while coroutine.status(generator) ~= "dead" do
        local _, value = coroutine.resume(generator)
        if value ~= nil then
            result = result .. value
        end
    end

    return result
end

do
    local build = svad.newBuildConfiguration { buildFolder = "build/" }
    local gcc = build:rule {
        name = "compileC",
        command = "gcc -MD -MF $out.d $cflags -c $in -o $out",
    }

    local ld = build:rule {
        name = "linker",
        command = "ld $ldflags $in -o $out",
    }

    build:buildPipe {
        gcc {
            input = "main.c",
            output = svad.toExtension("o"),
        },
        ld {
            output = "main",
        },
        build:buildCommand {
            command = "objcopy -O binary $in $out",
            output = "main.bin"
        }
    }

    print(exportToString(build))
end


do
    local build = svad.newBuildConfiguration {}
    local rules = build:addCComponent {
        cflags = "-I.",
    }

    build:buildPipe {
        rules.cc {
            input = "main.c",
            output = svad.toExtension("o"),
        },
        rules.ld {
            output = "main",
        },
    }

    --print(exportToString(build))
end
