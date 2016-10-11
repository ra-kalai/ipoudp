return {
  object_files = {
    {'.o', 'ltun/ltun.o' },
  },
  luaopen = {
    {'ltun', 'luaopen_ltun'},
  }
}
