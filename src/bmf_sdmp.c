#include <zlib.h>
#include <stdio.h>
#include <stdint.h>
#include <getopt.h>
#include <math.h>
#include <string.h>
#include <omp.h>
#include <stdlib.h>
#include "cstr_util.h"
#include "bmf_hashdmp.h"

void print_usage(char *argv[])
{
		fprintf(stderr, "Usage: %s <options> -i <Index.seq> <Fq.R1.seq> <Fq.R2.seq>"
						"\nFlags:\n"
						"-t: Homopolymer failure threshold. A molecular barcode with"
						" a homopolymer of length >= this limit is flagged as QC fail."
						"Default: 10.\n"
						"-o: Temporary fastq file prefix.\n"
						"-i: Index fastq path. Required.\n"
						"-n: Number of nucleotides at the beginning of the barcode to use to split the output.\n"
						"-z: Flag to optionally pipe to gzip while producing final fastqs. Default: False.\n"
						"-g: Gzip compression ratio if piping to gzip (-z). Default: 1 (weak compression).\n"
						"-s: Number of bases from reads 1 and 2 with which to salt the barcode. Default: 0.\n"
						"-m: Number of bases in the start of reads to skip when salting. Default: 1.\n"
						"-d: Flag to run hash dmp. Default: False.\n"
						"-p: Number of threads to use if running hash_dmp. Default: 4.\n"
						"-v: Set notification interval for split. Default: 1000000.\n"
						"-c: Flag to optionally cat all files together in one command. Faster than sequential cats, but might break."
						"In addition, won't work for enormous filenames or too many arguments. Default: False.\n"
						"-r: Path to flat text file with rescaled quality scores. If not provided, it will not be used.\n"
						"-w: Flag to leave temporary files instead of deleting them, as in default behavior.\n"
						"-f: If running hash_dmp, this sets the Final Fastq Prefix. \n",
						argv[0]);
}

static mark_splitter_t *splitmark_core_rescale(marksplit_settings_t *settings)
{
	if(strcmp(settings->input_r1_path, settings->input_r2_path) == 0) {
		fprintf(stderr, "[E:%s]Input read paths are the same {'R1': %s, 'R2': %s}. WTF!\n",
                __func__, settings->input_r1_path, settings->input_r2_path);
		exit(EXIT_FAILURE);
	}
	else
		fprintf(stderr, "[%s] Path to index fq: %s.\n", __func__, settings->index_fq_path);
	gzFile fp_read1, fp_read2, fp_index;
	kseq_t *seq1 = NULL, *seq2 = NULL, *seq_index = NULL;
	int l1, l2, l_index;
	mark_splitter_t *splitter_ptr = (mark_splitter_t *)malloc(sizeof(mark_splitter_t));
	*splitter_ptr = init_splitter(settings);
	if(!isfile(settings->input_r1_path) ||
	   !isfile(settings->input_r2_path) ||
	   !isfile(settings->index_fq_path)) {
		fprintf(stderr, "[E:%s] At least one input path ('%s', '%s', '%s') is not a file. Abort!\n", __func__,
				settings->input_r1_path, settings->input_r2_path, settings->index_fq_path);
		exit(EXIT_FAILURE);
	}
	// Open fastqs
	fp_read1 = gzopen(settings->input_r1_path, "r"), fp_read2 = gzopen(settings->input_r2_path, "r");
    seq1 = kseq_init(fp_read1), seq2 = kseq_init(fp_read2);
	l1 = kseq_read(seq1), l2 = kseq_read(seq2);

	fp_index = gzopen(settings->index_fq_path, "r");
	seq_index = kseq_init(fp_index),
	l_index = kseq_read(seq_index);

	uint64_t bin = 0;
	int count = 0;
	char pass_fail = '1';
	tmp_mseq_t *tmp = init_tm_ptr(seq1->seq.l, seq_index->seq.l + 2 * settings->salt);
	if(l1 < 0 || l2 < 0 || l_index < 0) {
		fprintf(stderr, "[E:%s] Could not read input fastqs. Abort mission!\n", __func__);
		exit(EXIT_FAILURE);
	}
	fprintf(stderr, "[%s] Splitter now opening files R1 ('%s'), R2 ('%s'), index ('%s').\n",
			__func__, settings->input_r1_path, settings->input_r2_path, settings->index_fq_path);
	mseq_t *rseq1 = mseq_init(seq1, settings->rescaler, 0); // rseq1 is initialized
	mseq_t *rseq2 = mseq_init(seq2, settings->rescaler, 1); // rseq2 is initialized
	memcpy(rseq1->barcode, seq1->seq.s + settings->offset, settings->salt); // Copy in the appropriate nucleotides.
	memcpy(rseq1->barcode + settings->salt, seq_index->seq.s, seq_index->seq.l); // Copy in the barcode
	memcpy(rseq1->barcode + settings->salt + seq_index->seq.l, seq2->seq.s + settings->offset, settings->salt);
	rseq1->barcode[settings->salt * 2 + seq_index->seq.l] = '\0';
	update_mseq(rseq1, seq1, settings->rescaler, tmp, 0, 0, 0);
	update_mseq(rseq2, seq2, settings->rescaler, tmp, 0, 1, 0);
	pass_fail = test_hp(rseq1->barcode, settings->hp_threshold);
	bin = get_binner_type(rseq1->barcode, settings->n_nucs, uint64_t);
	SALTED_MSEQ_2_FQ(splitter_ptr->tmp_out_handles_r1[bin], rseq1, rseq1->barcode, pass_fail);
	SALTED_MSEQ_2_FQ(splitter_ptr->tmp_out_handles_r2[bin], rseq2, rseq1->barcode, pass_fail);
	//fprintf(stderr, "Now beginning to loop through file.\n");
	while ((l1 = kseq_read(seq1)) >= 0 && (l2 = kseq_read(seq2) >= 0)
			&& (l_index = kseq_read(seq_index)) >= 0) {
		if(!(++count % settings->notification_interval)) {
			fprintf(stderr, "Number of records processed: %i.\n", count);
		}
		memcpy(rseq1->barcode, seq1->seq.s + settings->offset, settings->salt); // Copy in the appropriate nucleotides.
		memcpy(rseq1->barcode + settings->salt, seq_index->seq.s, seq_index->seq.l); // Copy in the barcode
		memcpy(rseq1->barcode + settings->salt + seq_index->seq.l, seq2->seq.s + settings->offset, settings->salt);
		update_mseq(rseq1, seq1, settings->rescaler, tmp, 0, 0, 0);
		update_mseq(rseq2, seq2, settings->rescaler, tmp, 0, 1, 0);
		pass_fail = test_hp(rseq1->barcode, settings->hp_threshold);
		bin = get_binner_type(rseq1->barcode, settings->n_nucs, uint64_t);
		SALTED_MSEQ_2_FQ(splitter_ptr->tmp_out_handles_r1[bin], rseq1, rseq1->barcode, pass_fail);
		SALTED_MSEQ_2_FQ(splitter_ptr->tmp_out_handles_r2[bin], rseq2, rseq1->barcode, pass_fail);
	}
	tm_destroy(tmp);
	mseq_destroy(rseq1);
	mseq_destroy(rseq2);
	kseq_destroy(seq1);
	kseq_destroy(seq2);
	kseq_destroy(seq_index);
	gzclose(fp_read1);
	gzclose(fp_read2);
	gzclose(fp_index);
	for(count = 0; count < settings->n_handles; ++count) {
		fclose(splitter_ptr->tmp_out_handles_r1[count]);
		fclose(splitter_ptr->tmp_out_handles_r2[count]);
		splitter_ptr->tmp_out_handles_r1[count] = NULL;
		splitter_ptr->tmp_out_handles_r2[count] = NULL;
	}
	return splitter_ptr;
}

void print_opt_err(char *argv[], char *optarg)
{
	print_usage(argv);
	fprintf(stderr, "Unrecognized option %s. Abort!\n", optarg);
	exit(1);
}

int fqms_main(int argc, char *argv[])
{
	// Build settings struct
	marksplit_settings_t settings = {
		.hp_threshold = 10,
		.n_nucs = 2,
		.index_fq_path = NULL,
		.output_basename = NULL,
		.input_r1_path = NULL,
		.input_r2_path = NULL,
		.n_handles = 0,
		.notification_interval = 1000000,
		.run_hash_dmp = 0,
		.panthera = 0,
		.gzip_output = 0,
		.ffq_prefix = NULL,
		.salt = 0,
		.offset = 1,
		.threads = 4,
		.gzip_compression = 1,
		.rescaler = NULL,
		.rescaler_path = NULL,
		.cleanup = 1
	};

	int c;
	while ((c = getopt(argc, argv, "t:o:i:n:m:s:f:u:p:g:v:r:hdczw?")) > -1) {
		switch(c) {
			case 'c': settings.panthera = 1; break;
			case 'd': settings.run_hash_dmp = 1; break;
			case 'f': settings.ffq_prefix = strdup(optarg); break;
			case 'i': settings.index_fq_path = strdup(optarg); break;
			case 'm': settings.offset = atoi(optarg); break;
			case 'n': settings.n_nucs = atoi(optarg); break;
			case 'o': settings.output_basename = strdup(optarg);break;;
			case 'p': settings.threads = atoi(optarg); break;
			case 's': settings.salt = atoi(optarg); break;
			case 't': settings.hp_threshold = atoi(optarg); break;
			case 'v': settings.notification_interval = atoi(optarg); break;
			case 'z': settings.gzip_output = 1; break;
			case 'g': settings.gzip_compression = atoi(optarg); if(settings.gzip_compression > 9) settings.gzip_compression = 9; break;
			case 'w': settings.cleanup = 0; break;
			case 'r':
				fprintf(stderr, "About to parse in rescaler.\n");
				settings.rescaler_path = strdup(optarg); settings.rescaler = parse_1d_rescaler(settings.rescaler_path);
				fprintf(stderr, "Parsed rescaler.\n"); break;
			case '?': // Fall-through
			case 'h': print_usage(argv); return 0;
			default: print_opt_err(argv, optarg);
		}
	}

	increase_nofile_limit(settings.threads);
	omp_set_num_threads(settings.threads);

	settings.n_handles = ipow(4, settings.n_nucs);
	if(settings.n_handles * 3 > get_fileno_limit()) {
		int o_fnl = get_fileno_limit();
		increase_nofile_limit(kroundup32(settings.n_handles));
		fprintf(stderr, "Increased nofile limit from %i to %i.\n", o_fnl,
				kroundup32(settings.n_handles));
	}

    if(argc == 1) {
        print_usage(argv);
        return EXIT_SUCCESS;
    }

	if(argc - 1 != optind + 1) {
		fprintf(stderr, "[E:%s] Both read 1 and read 2 fastqs are required. See usage.\n", __func__);
		print_usage(argv);
		return 1;
	}
	settings.input_r1_path =  strdup(argv[optind]);
	settings.input_r2_path =  strdup(argv[optind + 1]);

	if(!settings.index_fq_path) {
		fprintf(stderr, "[E:%s] Index fastq required. See usage.\n", __func__);
		print_usage(argv);
		return 1;
	}
	if(!settings.output_basename) {
		settings.output_basename = (char *)malloc(21);
		rand_string(settings.output_basename, 20);
		fprintf(stderr, "[%s] Mark/split prefix not provided. Defaulting to random string ('%s').\n",
				__func__, settings.output_basename);
	}

/*
	fprintf(stderr, "Hey, can I even read this fastq? %s, %s, %i", seq1->seq.s, seq1->qual.s, l);
	fprintf(stderr, "Hey, my basename is %s\n", settings.output_basename);
*/
	mark_splitter_t *splitter = splitmark_core_rescale(&settings);
	if(settings.run_hash_dmp) {
		fprintf(stderr, "[%s] Now executing hashmap-powered read collapsing and molecular demultiplexing.\n",
		                __func__);
		if(!settings.ffq_prefix) {
			settings.ffq_prefix = make_default_outfname(settings.input_r2_path, ".dmp.final");
		}
		// Whatever I end up putting into here.
		splitterhash_params_t *params = init_splitterhash(&settings, splitter);
		fprintf(stderr, "[%s] Running dmp block in parallel with %i threads.\n", __func__, settings.threads);
		#pragma omp parallel
		{
			#pragma omp for schedule(dynamic, 1)
			for(int i = 0; i < settings.n_handles; ++i) {
				fprintf(stderr, "[%s] Now running hash dmp core on input filename %s and output filename %s.\n",
						__func__, params->infnames_r1[i], params->outfnames_r1[i]);
				hash_dmp_core(params->infnames_r1[i], params->outfnames_r1[i]);
			}
		}
		#pragma omp parallel
		{
			#pragma omp for schedule(dynamic, 1)
			for(int i = 0; i < settings.n_handles; ++i) {
				fprintf(stderr, "[%s] Now running hash dmp core on input filename %s and output filename %s.\n",
						__func__, params->infnames_r2[i], params->outfnames_r2[i]);
				hash_dmp_core(params->infnames_r2[i], params->outfnames_r2[i]);
				if(settings.cleanup) {
				    char tmpbuf[500];
					sprintf(tmpbuf, "rm %s %s", params->infnames_r1[i], params->infnames_r2[i]);
                    CHECK_CALL(tmpbuf);
				}
			}
		}
		// Remove temporary split files
		char del_buf[500];
		char cat_buff2[CAT_BUFFER_SIZE];
		char cat_buff1[CAT_BUFFER_SIZE];
		// Make sure that both files are empty.
		char cat_buff[CAT_BUFFER_SIZE];
		char ffq_r1[200];
		char ffq_r2[200];
		sprintf(ffq_r1, settings.gzip_output ? "%s.R1.fq.gz": "%s.R1.fq", settings.ffq_prefix);
		sprintf(ffq_r2, settings.gzip_output ? "%s.R2.fq.gz": "%s.R2.fq", settings.ffq_prefix);
		sprintf(cat_buff, "> %s", ffq_r1);
		CHECK_CALL(cat_buff);
		sprintf(cat_buff, "> %s", ffq_r2);
		CHECK_CALL(cat_buff);
		if(!settings.panthera) {
			for(int i = 0; i < settings.n_handles; ++i) {
				// Clear files if present
				if(settings.gzip_output)
					sprintf(cat_buff, "cat %s | pigz -p %i -%i - >> %s", params->outfnames_r1[i],
							settings.threads >= 2 ? settings.threads >> 1: 1,
							settings.gzip_compression, ffq_r1);
				else
					sprintf(cat_buff, "cat %s >> %s", params->outfnames_r1[i], ffq_r1);
				FILE *p1 = popen(cat_buff, "w");

				if(settings.gzip_output)
					sprintf(cat_buff, "cat %s | pigz -p %i -%i - >> %s", params->outfnames_r2[i],
							settings.threads >= 2 ? settings.threads >> 1: 1,
							settings.gzip_compression, ffq_r2);
				else
					sprintf(cat_buff, "cat %s >> %s", params->outfnames_r2[i], ffq_r2);
				FILE *p2 = popen(cat_buff, "w");
				if(pclose(p2) || pclose(p1)) {
					fprintf(stderr, "[E:%s] System call failed. Command : '%s'.\n", __func__, cat_buff);
					exit(EXIT_FAILURE);
				}
			}
		}
		else {
			sprintf(cat_buff1, "/bin/cat ");
			sprintf(cat_buff2, "/bin/cat ");
			for(int i = 0; i < settings.n_handles; ++i) {
				strcat(cat_buff1, params->outfnames_r1[i]);
				strcat(cat_buff1, " ");
				strcat(cat_buff2, params->outfnames_r2[i]);
				strcat(cat_buff2, " ");
			}
			if(settings.gzip_output) {
				sprintf(del_buf, " | pigz -p %i -%i -", settings.threads >= 2 ? settings.threads >> 1: 1, settings.gzip_compression);
				strcat(cat_buff1, del_buf);
				strcat(cat_buff2, del_buf);
			}
			strcat(cat_buff1, " > ");
			strcat(cat_buff1, ffq_r1);
			strcat(cat_buff2, " > ");
			strcat(cat_buff2, ffq_r2);
			FILE *c1_popen = popen(cat_buff1, "w");
			CHECK_CALL(cat_buff2);
			if(pclose(c1_popen)) {
				fprintf(stderr, "[E:%s] First cat command failed. Abort!\n", __func__);
				exit(EXIT_FAILURE);
			}
			fprintf(stderr, "[%s] Now cleaning up intermediate files.\n", __func__);
			#pragma omp parallel for shared(params)
			for(int i = 0; i < params->n; ++i) {
				char tmpbuf[500];
				sprintf(tmpbuf, "rm %s %s", params->outfnames_r1[i], params->outfnames_r2[i]);
				popen(tmpbuf, "w");
			}
			fprintf(stderr, "[%s] Finished cleaning up intermediate files.\n", __func__);
			//fprintf(stderr, "Not executing %s today. Eh.\n", cat_buff1);
		}
		splitterhash_destroy(params);
	}
	splitter_destroy(splitter);
	FREE_SETTINGS(settings);
	return 0;
}