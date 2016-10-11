return {
  object_files = {
    {'.o', 'lua-longhair/src/main.o' },
    {'.o', 'lua-longhair/longhair/longhair-mobile/cauchy_256.o' },
  },
  luaopen = {
    {'longhair', 'luaopen_longhair'},
  }
}
