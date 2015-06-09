__author__ = 'dnephi'

import unittest
import sys
import subprocess
from utilBMF.HTSUtils import pFastqFile
from MawCluster.BCFastq import (cFRF_helper as compareFqRecsFast,
                                pairedFastqConsolidate, singleFastqConsolidate)

class MyTestCase(unittest.TestCase):

    def tearDown(self):
        pass

    def setUp(self):
        self.handle = pFastqFile("../data/TestR1.fastq")
        self.prefastqs = [i for i in self.handle]

    def test_dmp(self):
        assert compareFqRecsFast(self.prefastqs) == (
            '@MISEQ-M00736:68:000000000-A8D2D:1:2117:26553:9909 1:N:0:ACAGTG|'
            'FP=IndexPass|BS=AAAAAATGGACCCATTAACC|FM=3|ND=0|FA=3,3,3,3,3,3,3,'
            '3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,'
            '3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3|PV'
            '=101,102,102,101,102,114,111,114,111,113,106,113,108,113,114,114'
            ',112,113,113,111,113,87,109,113,112,113,113,113,114,111,114,113,'
            '114,111,113,113,114,113,114,106,113,112,114,113,103,113,111,113,'
            '114,114,114,112,110,111,113,113,114,114,110,112,113,113,113,114,'
            '114,112,114,113,108,108\nAAATCGGGTCACTCCCACCTGAATACTGCGCTTTTCCGA'
            'TCGGCTTAAAAAATGGCGCACCACGAGATTA\n+\n~~~~~~~~~~~~~~~~~~~~~x~~~~~~'
            '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n')

    def test_pfc(self):
        pass

    def test_sfc(self):
        singleFastqConsolidate("../data/TestR1.fastq")
        conFq = open("TestR1.cons.fastq")
        assert conFq.readlines() == ['@AAAAAATGGACCCATTAACC 1:N:0:ACAGTG|FP=IndexPass|BS=AAAAAATGGACCCATTAACC|FM=3|ND=0|FA=3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3|PV=101,102,102,101,102,114,111,114,111,113,106,113,108,113,114,114,112,113,113,111,113,87,109,113,112,113,113,113,114,111,114,113,114,111,113,113,114,113,114,106,113,112,114,113,103,113,111,113,114,114,114,112,110,111,113,113,114,114,110,112,113,113,113,114,114,112,114,113,108,108\n', 'AAATCGGGTCACTCCCACCTGAATACTGCGCTTTTCCGATCGGCTTAAAAAATGGCGCACCACGAGATTA\n', '+\n', '~~~~~~~~~~~~~~~~~~~~~x~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n']
        subprocess.check_call("rm TestR1.cons.fastq",shell=True)
        conFq.close()

if __name__ == '__main__':
    unittest.main()
