ipoudp:
	git submodule init 
	git submodule update 
	( cd extra/lem/ ; ./configure --with-lua=builtin ; make)    && \
	( cd extra/lua-longhair/ ; make LUA_CFLAGS="-I../lem/lua" ) && \
	( cd extra/ltun/ ; make LUA_CFLAGS="-I../lem/lua" )         && \
	( cd extra/lua-lz4/ ; make LUA_INCDIR="../lem/lua" )        && \
	( cd extra/lem/ ; make bin/lem-s V=s LEM_EXTRA_PACK=../../ipoudp.lempack.lua:../lua-lz4.lempack.lua:../ltun.lempack.lua:../lualonghair.lempack.lua)
	mv extra/lem/bin/lem-s ipoudp

clean:
	( cd extra/lem/ ; make clean)           && \
	( cd extra/lua-longhair/ ; make clean ) && \
	( cd extra/ltun/ ; make clean)          && \
	( cd extra/lua-lz4/ ; make clean )

