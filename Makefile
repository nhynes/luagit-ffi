#!/usr/bin/env make -f

LIBGIT_INCLUDE_DIR ?= /usr/include
INSTDIR = "$(LUADIR)/luagit-ffi"

all: ffi.lua

.PHONY: ffi.lua
ffi.lua:
	$(CC) -E "$(LIBGIT_INCLUDE_DIR)/git2.h" -o git2.i
	sed -e 's/#.*$$//' -e '/^$$/d' -i git2.i
	echo "local ffi = require 'ffi'\nffi.cdef[[" > ffi_hdr.lua
	cat ffi_hdr.lua git2.i > ffi.lua
	echo "]]\nreturn ffi.load('libgit2')" >> ffi.lua
	rm ffi_hdr.lua git2.i

install:
	mkdir -p INSTDIR
	cp init.lua INSTDIR
	cp ffi.lua INSTDIR

clean:
	rm ffi.lua
