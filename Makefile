######################################
# Makefile written by Daniel Baker   #
#     d.nephi.baker@gmail.com       #
######################################

CC=gcc
GIT_VERSION := $(shell git describe --abbrev=4 --dirty --always)
FLAGS= -Wall -fopenmp -DVERSION=\"$(GIT_VERSION)\" -std=gnu99
LD= -lm -lz
INCLUDE= -Ihtslib -Iinclude -I.
LIB=
INSTALL=/usr/bin/install -c

prefix = /usr/local
bindir = $(prefix)/bin
binprefix =

OPT_FLAGS = -finline-functions -O3 -DNDEBUG -flto -fivopts -Wno-unused-function -Wno-unused-variable -Wno-strict-aliasing 
DB_FLAGS = -Wno-unused-function -Wno-strict-aliasing
PG_FLAGS = -Wno-unused-function -pg -DNDEBUG -O2 -Wno-strict-aliasing
UR_FLAGS = $(OPT_FLAGS) -DUNROLL

IGAMC_INC = include/igamc_cephes.c

SOURCES = htslib/sam.c include/sam_opts.c src/bmf_dmp.c include/igamc_cephes.c src/bmf_hashdmp.c \
		  src/bmf_sdmp.c src/bmf_rsq.c src/bmf_famstats.c src/bmf_vetter.c dlib/bed_util.c include/bedidx.c \
		  src/bmf_sort.c src/bmf_err.c dlib/io_util.c dlib/nix_util.c \
		  lib/kingfisher.c dlib/bam_util.c src/bmf_mark_unclipped.c src/bmf_cap.c lib/mseq.c lib/splitter.c \
		  src/bmf_main.c

# In case you want to make a debug or profile build without changing the .o/.c rules.
P_OBJS = $(SOURCES:.c=.po)
D_OBJS = $(SOURCES:.c=.dbo)
OBJS = $(SOURCES:.c=.o)

.PHONY: all clean install

all: libhts.a bmftools bmftools_db bmftools_p

install: all
	$(INSTALL) bmftools $(bindir)/$(binprefix)bmftools
	$(INSTALL) bmftools_p $(bindir)/$(binprefix)bmftools_p
	$(INSTALL) bmftools_db $(bindir)/$(binprefix)bmftools_db

%.o: %.c
	$(CC) -c $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) $< -o $@

%.po: %.c
	$(CC) -c $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(PG_FLAGS) $< -o $@

%.dbo: %.c
	$(CC) -c $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(DB_FLAGS) $< -o $@

libhts.a:
	cd htslib && make && cp libhts.a ../
bmftools_db: $(D_OBJS) libhts.a
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(DB_FLAGS) $(D_OBJS) libhts.a -o bmftools_db
bmftools_p: $(P_OBJS) libhts.a
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(PG_FLAGS) $(P_OBJS) libhts.a -o bmftools_p
bmftools: $(OBJS) libhts.a
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) $(OBJS) libhts.a -o bmftools


clean:
	rm -f *.a && rm -f *.o && rm -f bmftools* && rm -f src/*.o && rm -f dlib/*.o && \
		rm -f include/*.o && rm -f lib/*.o && cd htslib && make clean


