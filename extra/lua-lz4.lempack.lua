return {
  object_files = {
    {'.o', 'lua-lz4/lz4/lz4.o' },
    {'.o', 'lua-lz4/lz4/lz4hc.o' },
    {'.o', 'lua-lz4/lz4/lz4frame.o' },
    {'.o', 'lua-lz4/lz4/xxhash.o '},
    {'.o', 'lua-lz4/lua_lz4.o' },
  },
  luaopen = {
    {'lz4', 'luaopen_lz4'},
  }
}
