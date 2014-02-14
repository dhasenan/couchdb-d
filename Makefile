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
lib_build_params= -I../out/di ../out/heaploop.a

build: heaploop-couchdb-local

heaploop-couchdb-build: lib/*.d
	mkdir -p out
	(cd lib; $(DC) -Hd../out/di/ -c -of../out/couched.o -op *.d $(lib_build_params) $(DFLAGS))
	ar -r out/couched.a out/couched.o

heaploop-couchdb-local: deps/heaploop heaploop-couchdb-build

examples: heaploop-couchdb-local
	(cd examples; $(DC) -of../out/albums_example -op *.d ../lib/*.d -I../out/di ../out/heaploop.a $(DFLAGS))
	chmod +x out/./albums_example
	out/./albums_example $(ARGS)

.PHONY: clean

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

