#ifndef KHASH_DMP_CORE_H
#define KHASH_DMP_CORE_H
#include "uthash.h"
#include "kingfisher.h"
#include "bmf_dmp.h"
#include "mseq.h"
#include <assert.h>

KHASH_MAP_INIT_STR(dmp, KingFisher_t *)
void hash_dmp_core(char *infname, char *outfname);
int hash_dmp_main(int argc, char *argv[]);
extern void splitterhash_destroy(splitterhash_params_t *params);
extern splitterhash_params_t *init_splitterhash(mssi_settings_t *settings_ptr, mark_splitter_t *splitter_ptr);
extern splitterhash_params_t *init_splitterhash_mss(mss_settings_t *settings_ptr, mark_splitter_t *splitter_ptr);
void stranded_hash_dmp_core(char *infname, char *outfname);

//CONST extern inline char *mem_view(char *);
typedef struct HashKing {
	UT_hash_handle hh;
	char id[MAX_BARCODE_LENGTH + 1];
	KingFisher_t *value;
}hk_t;



static inline void cp_view2buf(char *view, char *buf)
{
	FOREVER {
		switch(*view) {
			case '\0': // Fall-through
			case '|': *buf++ = '\0'; return;
			default: *buf++ = *view++;
		}
	}
}


tmpvars_t *init_tmpvars_p(char *bs_ptr, int blen, int readlen);


static inline void tmpvars_destroy(tmpvars_t *tmp)
{
	free(tmp->buffers), free(tmp), tmp = NULL;
}


/* @func
 * Copies the barcode sequence from a fastq comment field into a buffer
 * :param: seq - [arg/kseq_t *] a filled-in kseq object.
 * :param: buf - a pre-allocated buffer or malloc'd char_ptr with enough space for the barcode and the null terminus.
 */
#define cp_bs2buf(seq, buf) cp_view2buf(barcode_mem_view(seq), buf)



#endif // KHASH_DMP_CORE_H
