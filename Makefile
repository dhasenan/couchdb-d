DC=dmd
OS_NAME=$(shell uname -s)
MH_NAME=$(shell uname -m)
DFLAGS=
ifeq (${DEBUG}, 1)
	DFLAGS=-debug -gc -gs -g
else
	DFLAGS=-O -release -inline -noboundscheck
endif
ifeq (${OS_NAME},Darwin)
	DFLAGS+=-L-framework -LCoreServices 
endif
ifeq (${lib_build_params}, )
	lib_build_params= -I../out/di ../out/heaploop.a
endif

build: local

compile: lib/*.d
	mkdir -p out
	(cd lib; $(DC) -Hd../out/di/ -c -of../out/couched.o -op *.d $(lib_build_params) $(DFLAGS))
	ar -r out/couched.a out/couched.o

local: deps/heaploop compile

examples: local
	(cd examples; $(DC) -of../out/albums_example -op *.d ../lib/*.d -I../out/di ../out/heaploop.a $(DFLAGS))
	chmod +x out/./albums_example
	out/./albums_example $(ARGS)

.PHONY: clean copy-external

deps/heaploop:
	@echo "Compiling deps/heaploop"
	git submodule update --init --remote deps/heaploop
	mkdir -p out
	DEBUG=${DEBUG} $(MAKE) -C deps/heaploop clean
	DEBUG=${DEBUG} $(MAKE) -C deps/heaploop
	cp deps/heaploop/out/heaploop.a out/
	cp -r deps/heaploop/out/di/ out/di

clean:
	rm -rf out/*
	rm -rf deps/*

