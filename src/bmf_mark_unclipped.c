/*  unclipped.c -- a postprocessor for bwa to facilitate MEI calls.
*/

#include "dlib/bam_util.h"
#include "include/sam_opts.h"

static inline void add_multiple_tags(bam1_t *b1, bam1_t *b2)
{
	add_unclipped_mate_starts(b1, b2);
	add_sc_lens(b1, b2);
	add_fraction_aligned(b1, b2);
}

void add_unclipped(samFile *in, bam_hdr_t *hdr, samFile *ofp)
{
	abstract_pair_iter(in, hdr, ofp, &add_multiple_tags);
}

static int unclipped_usage(char *argv[]) {
	fprintf(stderr, "\n");
	fprintf(stderr, "Usage: bmftools %s <input.namesrt.bam> <output.bam>\n\n", argv[0]);
	fprintf(stderr, "Opts:\n-l	 Sets bam compression level. (Valid: 1-9).\n");
	fprintf(stderr, "Set output.bam to \'-\' or \'stdout\' to pipe results.\n");
	fprintf(stderr, "Set input.amesrt.bam to \'-\' or \'stdoin\' to read from stdin.\n");

	sam_global_opt_help(stderr, "-....");
	exit(EXIT_FAILURE);
}

typedef struct option option_t;


int mark_unclipped_main(int argc, char *argv[])
{
	int c;
	samFile *in, *out;
	bam_hdr_t *header;
	char wmode[3] = {'w', 'b', '\0'};
	sam_global_args ga;
	memset(&ga, 0, sizeof(ga));

	int level = -1; // This is never used uninitialized, but why not initialize it?
	while ((c = getopt(argc, argv, "l:?h")) >= 0) {
		switch (c) {
		case 'l': level = atoi(optarg); wmode[2] = level + '0'; break;
		case 'h': case '?': unclipped_usage(argv);
		}
	}

	if (optind + 2 > argc) unclipped_usage(argv);

	in = sam_open_format(argv[optind], "r", &ga.in);
	header = sam_hdr_read(in);
	if (header == NULL || header->n_targets == 0) {
		LOG_ERROR("input SAM '%s' does not have header. Abort!\n", argv[optind]);
	}

	sam_open_mode(wmode+1, argv[optind+1], NULL);
	out = sam_open_format(argv[optind+1], wmode, &ga.out);
	if (in == 0 || out == 0) {
		LOG_ERROR("fail to read/write input files ('%s', '%s')\n", argv[optind], argv[optind + 1]);
	}
	sam_hdr_write(out, header);

	add_unclipped(in, header, out);
	bam_hdr_destroy(header);
	if(sam_close(in)) {
		LOG_ERROR("Failed to close input file. Abort mission!\n");
	}
	if(sam_close(out)) {
		LOG_ERROR("Failed to close output file. Abort mission!\n");
	}
	return EXIT_SUCCESS;
}
