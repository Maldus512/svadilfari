package = "Svadilfari"
version = "0.1-1"
source = {
   url = "git://github.com/Maldus512/svadilfari"
}
description = {
   summary = "A simple and effective build configuration tool",
   detailed = [[]],
   license = "MIT" -- or whatever you like
}
dependencies = {
   "lua >= 5.4"
   -- If you depend on other rocks, add them here
}
build = {
    type = "builtin",
    modules = {
        svadilfari = "src/svadilfari.lua",
    },
    install = {
        bin = {
            "src/svad.lua",
        },
    },
}
