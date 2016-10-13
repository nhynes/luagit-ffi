package = "luagit-ffi"
version = "scm-1"

source = {
  url = "git://github.com/nhynes/luagit-ffi",
  tag = "master"
}

description = {
  summary = "LuaJIT FFI interface to libgit2",
  detailed = [[
  ]],
  homepage = "https://github.com/nhynes/luagit-ffi",
  license = "MIT"
}

dependencies = {}

build = {
  type = "make",
  build_variables = {
    LUA="$(LUA)",
    LUA_BINDIR="$(LUA_BINDIR)",
    LUA_INCDIR="$(LUA_INCDIR)",
    LUA_LIBDIR="$(LUA_LIBDIR)",
  },
  install_variables = {
    BINDIR="$(BINDIR)",
    CONFDIR="$(CONFDIR)",
    LIBDIR="$(LIBDIR)",
    LUADIR="$(LUADIR)",
    PREFIX="$(PREFIX)",
  }
}
