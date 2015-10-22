######################################
# Makefile written by Daniel Baker   #
#     d.nephi.baker@gmail.co m       #
#  Cribbed from Zev Kronenberg       #
######################################

CC=gcc
GIT_VERSION := $(shell git describe --abbrev=4 --dirty --always)
FLAGS= -Wall -fopenmp -DVERSION=\"$(GIT_VERSION)\" #-fpermissive # -fpermissive is crazy
LD= -lm -lz -lpthread 
INCLUDE= -Isrc -Ihtslib -Ihtslib/htslib -I. -Ilib -Iinclude
LIB=-Lhtslib -lhts

OPT_FLAGS = -O3 -DNDEBUG -finline-functions
DB_FLAGS = -fno-inline
GP_FLAGS = $(DB_FLAGS) -pg

IGAMC_INC= include/igamc_cephes.c

.PHONY: all clean

all: lh3sort libhts.a fqmarksplit crms bmfsort hash_dmp fam_stat copy

lh3sort:
	cd include/sort && make && cd ../..

libhts.a:
	cd htslib && make && cp libhts.a ../
fqmarksplit:
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) $(IGAMC_INC) src/fqmarksplit.c src/uthash_dmp_core.c -o fqmarksplit
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(DB_FLAGS) $(IGAMC_INC) src/fqmarksplit.c src/uthash_dmp_core.c -o fqmarksplit_db
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(DB_FLAGS) $(IGAMC_INC) -DNOPARALLEL src/fqmarksplit.c src/uthash_dmp_core.c -o fqmarksplit_np
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(GP_FLAGS) $(IGAMC_INC) src/fqmarksplit.c src/uthash_dmp_core.c -o fqmarksplit_p
crms:
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) src/crms.c include/igamc_cephes.c src/uthash_dmp_core.c -o crms
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(DB_FLAGS) src/crms.c include/igamc_cephes.c src/uthash_dmp_core.c -o crms_db
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(GP_FLAGS) src/crms.c include/igamc_cephes.c src/uthash_dmp_core.c -o crms_p
bmfsort:
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(DB_FLAGS) src/bmfsort.c -o bmfsort_db
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(GP_FLAGS) src/bmfsort.c -o bmfsort_p
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) src/bmfsort.c -o bmfsort
hash_dmp:
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) src/uthash_dmp.c include/igamc_cephes.c -o hash_dmp
dmp:
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) src/dmp.c include/igamc_cephes.c -o dmp
fam_stat:
	$(CC) $(FLAGS) $(INCLUDE) $(LIB) $(LD) $(OPT_FLAGS) src/fam_stat.c -o fam_stat
copy:
	mv hash_dmp crms crms_db crms_p bmfsort bmfsort_db bmfsort_p include/sort/lh3sort fqmarksplit fqmarksplit_db fqmarksplit_p fqmarksplit_np fam_stat bin/


clean:
	rm *.a && rm bin/* && cd htslib && make clean


