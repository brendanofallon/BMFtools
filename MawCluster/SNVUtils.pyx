from __future__ import division
from collections import defaultdict
import operator
from operator import methodcaller as mc

import pysam
import cython
cimport cython
import numpy as np
cimport numpy as np
from numpy import array as nparray
from math import log10 as mlog10
from cytoolz import map as cmap
pyFastaFile = pysam.FastaFile

from MawCluster.PileupUtils import PCInfo, AlleleAggregateInfo
from utilBMF import HTSUtils
from utilBMF.HTSUtils import printlog as pl
from utilBMF.HTSUtils import ThisIsMadness
from utilBMF.HTSUtils import ReadPairIsDuplex
from MawCluster.Probability import ConfidenceIntervalAAF

ctypedef np.longdouble_t dtype128_t

"""
This module contains a variety of tools for calling variants.
Currently, it primarily works with SNPs primarily with experimental
features present for structural variants
TODO: INFO field: discrepancy between a given allele's RSF and the average
Reverse Strand Fraction - RSF
Both Strands Support Variant - BS
Fraction of unmerged reads supporting variant - TF
Allele Fraction - AF
DP - Depth (Merged)
"""


class SNVCFLine:

    """
    Contains data for writing to a VCF Line, where each ALT has its own line.

    If reverseStrandFraction is negative, it means that that information was
    not provided at initialization.
    minNumSS is the minumum number of start/stop combinations required to
    support a variant call.
    """
    @cython.locals(minNumSS=cython.long, minNumFam=cython.long,
                   MaxPValue=cython.float,
                   reverseStrandFraction=cython.float,
                   minPVFrac=cython.float, minNumFam=cython.long,
                   minNumSS=cython.long, minFA=cython.long,
                   minDuplexPairs=cython.long, minAAF=dtype128_t,
                   maxAAF=dtype128_t, FailedFMReads=cython.long,
                   FailedQCReads=cython.long, FailedBQReads=cython.long,
                   FailedMQReads=cython.long, NDP=cython.long,
                   ampliconFailed=cython.long, FailedAFReads=cython.long,
                   minAF=cython.float)
    def __init__(self,
                 AlleleAggregateObject,
                 MaxPValue=1e-30,
                 ID=".",
                 DOCMerged="default",
                 DOCTotal="default",
                 TotalFracStr="default",
                 MergedFracStr="default",
                 TotalCountStr="default",
                 MergedCountStr="default",
                 FailedBQReads=-1, FailedMQReads=-1,
                 FailedQCReads=-1, FailedFMReads=-1, FailedAFReads=-1,
                 minNumFam=2,
                 minNumSS=2,
                 REF="default",
                 reverseStrandFraction=-1.0,
                 requireDuplex=True, minDuplexPairs=2,
                 minFracAgreedForFilter=0.666,
                 minFA=0, BothStrandAlignment=-1,
                 pValBinom=0.05, ampliconFailed=-1, NDP=-1,
                 EST="none", minAF=-1.):
        if(BothStrandAlignment < 0):
            raise ThisIsMadness("BothStrandAlignment required for SNVCFLine,"
                                " as it is used in determining whether or no"
                                "t to remove a call for a variant mapping to"
                                " only one strand.")
        assert REF != "default"
        self.REF = REF
        if(isinstance(AlleleAggregateObject, AlleleAggregateInfo) is False):
            raise HTSUtils.ThisIsMadness("VCFLine requires an AlleleAgg"
                                         "regateInfo for initialization")
        if(DOCMerged == "default"):
            raise HTSUtils.ThisIsMadness("DOC (Merged) required!")
        if(DOCTotal == "default"):
            raise HTSUtils.ThisIsMadness("DOC (Total) required!")
        self.NumStartStops = len(list(set(cmap(operator.attrgetter("ssString"),
                                              AlleleAggregateObject.recList))))
        self.CHROM = AlleleAggregateObject.contig
        self.POS = AlleleAggregateObject.pos + 1
        self.CONS = AlleleAggregateObject.consensus
        self.ALT = AlleleAggregateObject.ALT
        self.QUAL = AlleleAggregateObject.SumBQScore
        self.BothStrandSupport = AlleleAggregateObject.BothStrandSupport
        self.reverseStrandFraction = reverseStrandFraction
        self.AABothStrandAlignment = BothStrandAlignment
        self.ID = ID
        AC = AlleleAggregateObject.MergedReads
        DOC = AlleleAggregateObject.DOC
        minAAF, maxAAF = ConfidenceIntervalAAF(AC, DOCMerged, pVal=pValBinom)
        try:
            if(float(MaxPValue) < 10 ** (self.QUAL // -10)):
                if("FILTER" in dir(self)):
                    self.FILTER = operator.add(self.FILTER, ",LowQual")
                else:
                    self.FILTER = "LowQual"
                self.QUAL *= 0.1
                # This is entirely arbitrary...
            if(AlleleAggregateObject.BothStrandSupport is False and
               BothStrandAlignment):
                if("FILTER" in dir(self)):
                    self.FILTER = operator.add(
                        self.FILTER, ",OneStrandSupport")
                else:
                    self.FILTER = "OneStrandSupport"
            if(operator.le(self.NumStartStops, minNumSS) and
               operator.le(AC, minNumSS)):
                if("FILTER" in dir(self)):
                    self.FILTER = operator.add(
                        self.FILTER, ",InsufficientCoordinateSetsSupport")
                else:
                    self.FILTER = "InsufficientCoordinateSetsSupport"
            if(AlleleAggregateObject.NumberDuplexReads < minDuplexPairs):
                if("FILTER" in dir(self)):
                    self.FILTER += ",InsufficientDuplexSupport"
                else:
                    self.FILTER = "InsufficientDuplexSupport"
            if(AlleleAggregateObject.MFractionAgreed < minFracAgreedForFilter):
                if("FILTER" in dir(self)):
                    self.FILTER += ",DiscordantReadFamilies"
                else:
                    self.FILTER = "DiscordantReadFamilies"
            if("FILTER" not in dir(self)):
                self.FILTER = "PASS"
        except TypeError:
            print("TypeError! MaxPValue is: {}".format(MaxPValue))
            raise TypeError("MaxPValue not properly parsed.")
        if(self.ALT == AlleleAggregateObject.consensus):
            self.FILTER = "CONSENSUS"

        self.InfoFields = {"AC": AC,
                           "AF": 1. * AC / DOC,
                           "BNP": int(-10 * mlog10(pValBinom)),
                           "BQF": FailedBQReads,
                           "BS": AlleleAggregateObject.BothStrandSupport,
                           "BSA": BothStrandAlignment,
                           "TF": 1. * AlleleAggregateObject.TotalReads
                           / AlleleAggregateObject.DOCTotal,
                           "NSS": self.NumStartStops,
                           "MBP": AlleleAggregateObject.MBP,
                           "BPSD": AlleleAggregateObject.BPSD,
                           "FAF": FailedAFReads,
                           "FQC": FailedQCReads, "FFM": FailedFMReads,
                           "FSR": AlleleAggregateObject.FSR,
                           "MNCS": minNumSS, "MDP": minDuplexPairs,
                           "MFRAC": AlleleAggregateObject.MFractionAgreed,
                           "MINFRACCALL": AlleleAggregateObject.minFrac,
                           "MINFRACFILTER": minFracAgreedForFilter,
                           "MFA": AlleleAggregateObject.MFA,
                           "MINAF": minAF,
                           "MINFA": AlleleAggregateObject.minFA,
                           "MINAAF": minAAF, "MAXAAF": maxAAF,
                           "MQM": AlleleAggregateObject.AveMQ,
                           "MQB": AlleleAggregateObject.AveBQ,
                           "MMQ": AlleleAggregateObject.minMQ,
                           "MBQ": AlleleAggregateObject.minBQ,
                           "NDP": NDP, "QA": AlleleAggregateObject.SumBQScore,
                           "PFSD": AlleleAggregateObject.PFSD,
                           "NFSD": AlleleAggregateObject.NFSD,
                           "MPF": AlleleAggregateObject.MPF,
                           "NUMALL": AlleleAggregateObject.NUMALT,
                           "MQF": FailedMQReads,
                           "TND": AlleleAggregateObject.TND,
                           "TYPE": "snp",
                           "MAXNF": AlleleAggregateObject.maxNF,
                           "MNF": AlleleAggregateObject.MNF,
                           "PVC": MaxPValue,
                           "CONS": self.CONS,
                           "NDPS": AlleleAggregateObject.NumberDuplexReads}
        if(TotalCountStr != "default"):
            self.InfoFields["TACS"] = TotalCountStr
        if(TotalFracStr != "default"):
            self.InfoFields["TAFS"] = TotalFracStr
        if(MergedCountStr != "default"):
            self.InfoFields["MACS"] = MergedCountStr
        if(MergedFracStr != "default"):
            self.InfoFields["MAFS"] = MergedFracStr
        if(self.reverseStrandFraction >= 0):
            self.InfoFields["AARSF"] = self.reverseStrandFraction
            # All Alleles Reverse Read Fraction
        if(ampliconFailed >= 0):
            self.InfoFields["NAF"] = ampliconFailed
        self.InfoFields["RSF"] = AlleleAggregateObject.reverseStrandFraction
        if("AABPSD" in dir(AlleleAggregateObject)):
            self.InfoFields["AABPSD"] = AlleleAggregateObject.AABPSD
        if("AAMBP" in dir(AlleleAggregateObject)):
            self.InfoFields["AAMBP"] = AlleleAggregateObject.AAMBP
        self.InfoStr = ";".join(
            [key + "=" + str(self.InfoFields[key])
             for key in sorted(self.InfoFields.keys())])
        self.FormatFields = {"DP": DOC,
                             "DPA": AC,
                             "DPT": DOCTotal}
        ffkeys = self.FormatFields.keys()
        self.FormatStr = (
            ":".join(sorted(ffkeys)) +
            "\t" + ":".join(str(
                self.FormatFields[key]) for key in sorted(
                    ffkeys)))
        self.str = "\t".join(nparray([self.CHROM,
                                       self.POS,
                                       self.ID,
                                       self.CONS,
                                       self.ALT,
                                       self.QUAL,
                                       self.FILTER,
                                       self.InfoStr,
                                       self.FormatStr]).astype(str).tolist())

    def update(self):
        ffkeys = self.FormatFields.keys()
        self.FormatKey = ":".join(sorted(ffkeys))
        self.FormatValue = ":".join([str(self.FormatFields[key])
                                     for key in
                                     sorted(ffkeys)])
        self.FormatStr = (":".join(sorted(ffkeys)) + "\t" +
                          ":".join(
                              str(self.FormatFields[key])
                              for key in sorted(ffkeys)))
        self.InfoStr = ";".join([key + "=" + str(self.InfoFields[key])
                                 for key in sorted(self.InfoFields.keys())])

    def __str__(self):
        self.update()
        self.str = "\t".join(nparray([self.CHROM, self.POS,
                                      self.ID, self.REF, self.ALT,
                                      self.QUAL, self.FILTER, self.InfoStr,
                                      self.FormatStr]).astype(str).tolist())
        return self.str


class VCFPos:
    """
    Holds the multiple SNVCFLine Objects and other information
    for writing VCF lines for each alt at a given position.
    """
    @cython.locals(requireDuplex=cython.bint, keepConsensus=cython.bint,
                   minDuplexPairs=cython.long, MaxPValue=cython.float,
                   NDP=cython.long)
    def __init__(self, PCInfoObject,
                 MaxPValue=1e-18,
                 keepConsensus=True,
                 reference="default",
                 requireDuplex=True,
                 minDuplexPairs=2,
                 reverseStrandFraction="default",
                 minFracAgreed=0.0, minFA=0, experiment="",
                 NDP=-1, refHandle=None):
        if(isinstance(PCInfoObject, PCInfo) is False):
            raise HTSUtils.ThisIsMadness("VCFPos requires an "
                                         "PCInfo for initialization")
        if(refHandle is None):
            if(reference == "default"):
                HTSUtils.FacePalm("VCFPos requires a reference fasta.")
            refHandle = pyFastaFile(reference)
        else:
            assert isinstance(refHandle, pysam.cfaidx.FastaFile)
        if("amplicon" in PCInfoObject.experiment):
            ampliconFailed = PCInfoObject.ampliconFailed
        try:
            assert NDP >= 0
        except AssertionError:
            raise ThisIsMadness(
                "VCFPos requires the number of discordant pairs for initializ"
                "ation. Important QC step!")
        # Because bamtools is 0-based but vcfs are 1-based
        self.minAF = PCInfoObject.minAF
        self.pos = PCInfoObject.pos + 1
        self.minMQ = PCInfoObject.minMQ
        self.consensus = PCInfoObject.consensus
        self.TotalFracStr = PCInfoObject.TotalFracStr
        self.MergedFracStr = PCInfoObject.MergedFracStr
        self.TotalCountStr = PCInfoObject.TotalCountStr
        self.MergedCountStr = PCInfoObject.MergedCountStr
        self.REF = refHandle.fetch(PCInfoObject.contig, self.pos - 1, self.pos)
        self.FailedAFReads = PCInfoObject.FailedAFReads
        self.reverseStrandFraction = PCInfoObject.reverseStrandFraction
        self.AABothStrandAlignment = PCInfoObject.BothStrandAlignment
        self.requireDuplex = requireDuplex
        self.EST = PCInfoObject.excludedSVTagStr
        self.VCFLines = [SNVCFLine(
            alt, TotalCountStr=self.TotalCountStr,
            MergedCountStr=self.MergedCountStr,
            TotalFracStr=self.TotalFracStr,
            MergedFracStr=self.MergedFracStr,
            DOCMerged=PCInfoObject.MergedReads,
            DOCTotal=PCInfoObject.TotalReads,
            MaxPValue=MaxPValue,
            FailedBQReads=PCInfoObject.FailedBQReads,
            FailedMQReads=PCInfoObject.FailedMQReads,
            FailedQCReads=PCInfoObject.FailedQCReads,
            REF=self.REF, requireDuplex=self.requireDuplex,
            reverseStrandFraction=self.reverseStrandFraction,
            minDuplexPairs=minDuplexPairs,
            minFracAgreedForFilter=minFracAgreed,
            minFA=minFA, BothStrandAlignment=PCInfoObject.BothStrandAlignment,
            NDP=NDP, EST=self.EST, FailedAFReads=PCInfoObject.FailedAFReads,
            minAF=self.minAF)
            for alt in PCInfoObject.AltAlleleData]
        self.keepConsensus = keepConsensus
        if(self.keepConsensus):
            self.str = "\n".join([line.__str__()
                                  for line in
                                  self.VCFLines])
        else:
            self.str = "\n".join([line.__str__()
                                  for line in
                                  self.VCFLines
                                  if line.FILTER != "CONSENSUS"])
        self.DuplexRequired = requireDuplex
        self.minDuplexPairs = minDuplexPairs

    def __str__(self):
        cmap(mc("update"), self.VCFLines)
        self.str = "\n".join(cmap(mc("__str__"), self.VCFLines))
        return self.str


class HeaderFileFormatLine:

    """
    This class holds the fileformat line in a VCF.
    Defaults to VCFv4.1
    """

    def __init__(self, fileformat="VCFv4.1"):
        if(fileformat == "default"):
            self.fileformat = "VCFv4.1"
        else:
            self.fileformat = fileformat

    def __str__(self):
        self.str = "##fileformat={}".format(self.fileformat)
        return self.str


class HeaderInfoLine:

    """
    This class holds a VCF INFO header line.
    """

    def __init__(self, ID="default", Number="default", Type="default",
                 Description="default"):
        Types = "integer,float,string,flag,character,string"
        if(Type.lower() not in Types.lower().split(",")):
            raise ThisIsMadness("Invalid Type provided!")
        self.Type = Type

        Numbers = "A,G"
        try:
            self.Number = int(Number)
        except ValueError:
            if(Number) in Numbers.split(','):
                self.Number = Number
            else:
                raise ThisIsMadness("Invalid \"Number\" provided.")

        self.ID = ID.upper()

        if(Description != "default"):
            self.Description = Description
        else:
            raise ThisIsMadness("A description is required.")

    def __str__(self):
        self.str = ("##INFO=<ID="
                    "{},Number={},Type=".format(self.ID, self.Number) +
                    "{},Description={}>".format(self.Type, self.Description))
        return self.str


class HeaderFormatLine:

    """
    This class holds a VCF FORMAT header line.
    """

    def __init__(self, ID="default", Number="default", Type="default",
                 Description="default"):
        Types = "integer,float,string,character"
        if(Type.lower() not in Types.lower().split(",")):
            raise ThisIsMadness("Invalid Type provided!")
        self.Type = Type

        Numbers = "A,G"
        try:
            self.Number = int(Number)
        except ValueError:
            if(Number) in Numbers.split(','):
                self.Number = Number
            else:
                raise ThisIsMadness("Invalid \"Number\" provided.")

        self.ID = ID.upper()

        if(Description != "default"):
            self.Description = Description
        else:
            raise ThisIsMadness("A description is required.")

    def __str__(self):
        self.str = ("##FORMAT=<ID="
                    "{},Number={},Type=".format(self.ID, self.Number) +
                    "{},Description={}>".format(self.Type, self.Description))
        return self.str


class HeaderAltLine:

    """
    This class holds a VCF ALT header line.
    """

    def __init__(self, ID="default", Description="default"):
        Types = "DEL,INS,DUP,INV,CNV,DUP:TANDEM,DEL:ME,INS:ME"
        if(ID.upper() in Types.split(",")):
            self.ID = ID.upper()
        else:
            raise ThisIsMadness("VCF4.1 Specifications require that"
                                " this field be one of the following:"
                                " {}".format(Types.replace(",", ", ")))
        self.Description = Description

    def __str__(self):
        self.str = "##ALT=<ID={},Description={}>".format(self.ID,
                                                         self.Description)
        return self.str


class HeaderFilterLine:

    """
    This class holds a VCF FILTER header line.
    """

    def __init__(self, ID="default", Description="default"):
        self.ID = ID
        self.Description = Description

    def __str__(self):
        self.str = "##FILTER=<ID={},Description={}>".format(
            self.ID, self.Description)
        return self.str


class HeaderAssemblyLine:

    """
    This class holds a VCF assembly header line.
    """

    def __init__(self, assembly="default"):
        self.assembly = assembly

    def __str__(self):
        self.str = "##assembly={}".format(self.assembly)
        return self.str


class HeaderCommandLine:

    """
    This class holds a VCF command header line.
    """

    def __init__(self, commandStr="default"):
        self.commandStr = commandStr

    def __str__(self):
        self.str = "##commandline={}".format(self.commandStr)
        return self.str


class HeaderFunctionCallLine:

    """
    This class holds a VCF Function Call Line.
    """

    def __init__(self, callStr="default"):
        self.callStr = callStr

    def __str__(self):
        self.str = "##FunctionCall={}".format(self.callStr)
        return self.str


class HeaderFilterINFOGtLine:

    """
    This class holds a custom VCF header line for
    a filtering of a VCF.
    """

    def __init__(self, INFOTag="default", negation="default",
                 referenceValue="default",
                 referenceType="default"):
        self.INFOTag = INFOTag
        self.ID = "INFOValGt"
        self.Description = "INFO Tag Value > Reference Value"
        self.referenceValue = referenceValue
        self.referenceType = referenceType
        if(negation != "default"):
            self.negation = (negation.lower() == "true")
            if(referenceValue == "default"):
                ThisIsMadness(
                    "A reference value must be present if negation is set.")
        if(referenceType == "default"):
            referenceType = str  # Default behavior sets the type to string.

    def __str__(self):
        self.str = "##FILTER=<ID={},Description={},".format(
                   self.ID, self.Description)
        self.str += "Type={},Negated={},RVal={},INFOTag={}>".format(
                    self.referenceType, self.negation, self.referenceValue,
                    self.INFOTag)
        return self.str


class HeaderFilterINFOEqLine:

    """
    This class holds a custom VCF header line for
    a filtering of a VCF.
    """

    def __init__(self, INFOTag="default", negation="default",
                 referenceValue="default",
                 referenceType="default"):
        self.INFOTag = INFOTag
        self.ID = "INFOValEq"
        self.Description = "INFO Tag Value == Reference Value"
        self.referenceValue = referenceValue
        self.referenceType = referenceType
        if(negation != "default"):
            self.negation = (negation.lower() == "true")
            if(referenceValue == "default"):
                ThisIsMadness(
                    "A reference value must be present if negation is set.")
        if(referenceType == "default"):
            referenceType = str  # Default behavior sets the type to string.

    def __str__(self):
        self.str = "##FILTER=<ID={},Description={},".format(
                   self.ID, self.Description)
        self.str += "Type={},Negated={},RVal={},INFOTag={}>".format(
                    self.referenceType, self.negation, self.referenceValue,
                    self.INFOTag)
        return self.str


class HeaderCustomLine:

    """
    This class holds a custom VCF header line.
    """

    def __init__(self, customValue="default", customKey="default"):
        self.customValue = customValue
        self.customKey = customKey

    def __str__(self):
        self.str = "##{}={}".format(self.customKey, self.customValue)
        return self.str


class HeaderReferenceLine:

    """
    This class holds a VCF Reference header line.
    """

    def __init__(self, reference="default", isfile=False):
        self.reference = reference
        if(isinstance(isfile, bool)):
            self.isfile = isfile
        elif(isinstance(isfile, str)):
            if("true" in isfile.lower()):
                self.isfile = True
            elif("false" in isfile.lower()):
                self.isfile = False
            else:
                raise ValueError(
                    "isfile kwarg provided was not true or false!")
        else:
            raise ValueError(
                "isfile kwarg provided was not true or false!")

    def __str__(self):
        if(self.isfile is False):
            self.str = "##reference={}".format(self.reference)
        else:
            self.str = "##reference=file://{}".format(self.reference)
        return self.str


class HeaderContigLine:

    """
    This class holds a VCF Assembly header line.
    """

    def __init__(self, contig="default", length="default"):
        self.contig = contig
        try:
            self.length = int(length)
        except ValueError:
            raise ThisIsMadness("Length must be an integer!")

    def __str__(self):
        self.str = "##contig=<ID={},length={}>".format(
            self.contig, self.length)
        return self.str


"""
This next section contains the dictionaries which hold the
FILTER Header entries
Valid tags: PASS,OneStrandSupport,LowQual,CONSENSUS,
InsufficientCoordinateSetSupport,DiscordantReadFamilies
"""

HeaderFilterDict = {}
HeaderFilterDict["PASS"] = HeaderFilterLine(ID="PASS",
                                            Description="All filters passed")
HeaderFilterDict["InsufficientCoordinateSetSupport"] = HeaderFilterLine(
    ID="InsufficientCoordinateSetSupport",
    Description=("High quality but only supported by "
                 "reads with too few unique starts and stops."))
HeaderFilterDict["OneStrandSupport"] = HeaderFilterLine(
    ID="OneStrandSupport",
    Description="High quality but only supported by reads on one strand. Fil"
    "ter not added if all alleles only map to one strand.")
HeaderFilterDict["LowQual"] = HeaderFilterLine(
    ID="LowQual", Description="Low Quality, below P-Value Cutoff")
HeaderFilterDict["CONSENSUS"] = HeaderFilterLine(
    ID="CONSENSUS",
    Description="Not printed due to being the "
    "consensus sequence, not somatic.")
HeaderFilterDict["DiscordantReadFamilies"] = HeaderFilterLine(
    ID="DiscordantReadFamilies",
    Description="Minimum read agreement fraction not met.")


"""
This next section contains the dictionaries which hold the
INFO Header entries
Valid tags: AF,TF,BS,RSF,MQM,MQB,MMQ,MBQ,QA,NUMALL,BQF,MQF,
TYPE,PVC,TACS,TAFS,MACS,MAFS,NSS,AC,NDPS,AARSF,RSF,MNCS,MDP,MBP,AAMBP,
BPSD,AABPSD,MFRAC,MINFRACCALL,MINFRACFILTER,MFA,MINFA
"""

HeaderInfoDict = {}
HeaderInfoDict["AF"] = HeaderInfoLine(
    ID="AF",
    Type="Float",
    Description=("Allele Frequency, for each ALT allele, "
                 "in the same order as listed for Merged read families."),
    Number="A")
HeaderInfoDict["AC"] = HeaderInfoLine(
    ID="AC",
    Type="Integer",
    Description=("Allele Count, for each ALT allele, "
                 "in the same order as listed for Merged read families."
                 " Note: BMFTools writes VCFs one ALT per line."),
    Number="A")
HeaderInfoDict["NSS"] = HeaderInfoLine(
    ID="NSS",
    Type="Integer",
    Description=("Number of unique sets of starts & stops supporting ALT all"
                 "ele in the same order as listed for Merged read families."),
    Number="A")
HeaderInfoDict["TF"] = HeaderInfoLine(
    ID="TF",
    Type="Float",
    Description=("Total Allele Frequency, for each ALT allele, "
                 "in the same order as listed for unmerged read families,"
                 "IE, without having removed the duplicates."),
    Number="A")
HeaderInfoDict["FSR"] = HeaderInfoLine(
    ID="FSR",
    Type="Integer",
    Description="Number of reads left out of pileup due to SV tags.",
    Number=1)
HeaderInfoDict["RSF"] = HeaderInfoLine(
    ID="RSF",
    Type="Float",
    Description=("Fraction of reads supporting allele "
                 "aligned to reverse strand."),
    Number="A")
HeaderInfoDict["MQM"] = HeaderInfoLine(ID="MQM",
                                       Description="Mean Quality for Mapping",
                                       Number="A",
                                       Type="Float")

HeaderInfoDict["MQB"] = HeaderInfoLine(ID="MQB",
                                       Description="Mean Base Quality",
                                       Number="A",
                                       Type="Float")
HeaderInfoDict["MMQ"] = HeaderInfoLine(
    ID="MMQ",
    Description="Min Mapping Quality for reads used in variant calling.",
    Number="A",
    Type="Integer")
HeaderInfoDict["MBQ"] = HeaderInfoLine(
    ID="MBQ",
    Description="Min Base Quality for reads used in variant calling.",
    Number="A",
    Type="Integer")
HeaderInfoDict["QA"] = HeaderInfoLine(
    ID="QA",
    Description="Alternate allele quality sum in phred",
    Number="A",
    Type="Integer")
HeaderInfoDict["NUMALL"] = HeaderInfoLine(
    ID="NUMALL",
    Description="Number of unique alleles at position.",
    Number=1,
    Type="Integer")
HeaderInfoDict["BQF"] = HeaderInfoLine(
    ID="BQF",
    Description="Number of (merged) reads failed for low BQ.",
    Number=1,
    Type="Integer")
HeaderInfoDict["MQF"] = HeaderInfoLine(
    ID="MQF",
    Description="Number of (merged) reads failed for low MQ.",
    Number=1,
    Type="Integer")
HeaderInfoDict["TYPE"] = HeaderInfoLine(
    ID="TYPE",
    Description="The type of allele, either snp, mnp, ins, del, or complex.",
    Number="A",
    Type="String")
HeaderInfoDict["PVC"] = HeaderInfoLine(
    ID="PVC",
    Description="P-value cutoff used.",
    Number=1,
    Type="Float")
HeaderInfoDict["TACS"] = HeaderInfoLine(
    ID="TACS",
    Description="Total (Unmerged) Allele Count String.",
    Number=1,
    Type="String")
HeaderInfoDict["TAFS"] = HeaderInfoLine(
    ID="TAFS",
    Description="Total (Unmerged) Allele Frequency String.",
    Number=1,
    Type="String")
HeaderInfoDict["MACS"] = HeaderInfoLine(
    ID="MACS",
    Description="Merged Allele Count String.",
    Number=1,
    Type="String")
HeaderInfoDict["MAFS"] = HeaderInfoLine(
    ID="MAFS",
    Description="Merged Allele Frequency String.",
    Number=1,
    Type="String")
HeaderInfoDict["NDPS"] = HeaderInfoLine(
    ID="NDPS",
    Description="Number of Duplex Reads Supporting Variant",
    Number="A",
    Type="Integer")
HeaderInfoDict["AARSF"] = HeaderInfoLine(ID="AARSF",
                                         Description="The fraction of reads a"
                                         "t position supporting any allele pa"
                                         "ssing all filters mapped to the rev"
                                         "erse strand",
                                         Number=1,
                                         Type="Float")
HeaderInfoDict["RSF"] = HeaderInfoLine(ID="RSF", Description="Fraction of r"
                                       "eads for given allele passing all f"
                                       "ilters mapped to the reverse strand.",
                                       Number="A", Type="Float")
HeaderInfoDict["MNCS"] = HeaderInfoLine(ID="MNCS",
                                        Description="Minimum number of coordi"
                                        "nate sets for read pairs supporting "
                                        "variant to pass filter.",
                                        Number=1, Type="Integer")
HeaderInfoDict["MDP"] = HeaderInfoLine("MDP",
                                       Description="Minimum duplex pairs supp"
                                       "orting variant to pass filter.",
                                       Number=1,
                                       Type="Integer")
HeaderInfoDict["MBP"] = HeaderInfoLine(ID="MBP",
                                       Description="Mean base position in rea"
                                       "d for reads supporting variant passin"
                                       "g all filters. 0-based.",
                                       Number="A", Type="Float")
HeaderInfoDict["AAMBP"] = HeaderInfoLine(ID="AAMBP",
                                         Description="Mean base position in re"
                                         "ad for all reads at position passin"
                                         "g all filters. 0-based.",
                                         Number="A", Type="Float")
HeaderInfoDict["BPSD"] = HeaderInfoLine(ID="BPSD", Description="Standard dev"
                                        "iation of base position in read fo"
                                        "r reads supporting variant passing"
                                        " all filters.", Number="A",
                                        Type="Float")
HeaderInfoDict["AABPSD"] = HeaderInfoLine(ID="AABPSD",
                                          Description="Standard deviation of"
                                          " base position in read for all re"
                                          "ads at position passing filters.",
                                          Number=1, Type="Float")
HeaderInfoDict["MFRAC"] = HeaderInfoLine(
    ID="MFRAC", Description="Mean fraction of reads in a family supporting a "
    "nucleotide at this position", Number="A", Type="Float")
HeaderInfoDict["MINFRACFILTER"] = HeaderInfoLine(
    ID="MINFRACFILTER", Description="Minimum fraction of reads in a family in"
    "order to not be filtered out for discordance.", Number=1, Type="Float")
HeaderInfoDict["MINFRACCALL"] = HeaderInfoLine(
    ID="MINFRACCALL", Description="Minimum fraction of reads in a family "
    "to be included in variant call", Number=1, Type="Float")
HeaderInfoDict["MFA"] = HeaderInfoLine(
    ID="MFA", Description="Mean number of reads in a family agreeing on allel"
    "e.", Number="A", Type="Float")
HeaderInfoDict["MINFA"] = HeaderInfoLine(
    ID="MINFA", Description="Minimum number of agreeing reads in a family for"
    "that family to be included in variant call", Number=1, Type="Integer")
HeaderInfoDict["PFSD"] = HeaderInfoLine(
    ID="PFSD",
    Description="Standard deviation of Phred Fraction (summed phre"
                "d score over maximum summed phred score in family.",
    Number="A", Type="Float")
HeaderInfoDict["MPF"] = HeaderInfoLine(
    ID="MPF",
    Description="Mean Phred Fraction (summed phred score over maximum summed"
                " phred score in family) for families supporting this allele"
                ". If this is far from 1, there might be something suspiciou"
                "s going on.",
    Number="A", Type="Float")
HeaderInfoDict["EST"] = HeaderInfoLine(ID="EST",
                                       Description="Excluded SV Tags",
                                       Number=1, Type="String")
HeaderInfoDict["MFDN"] = HeaderInfoLine(
    ID="MFDN", Description="Maximum frequency expected for deamination noise",
                                       Number=1, Type="Float")
HeaderInfoDict["MFDNP"] = HeaderInfoLine(
    ID="MFDNP", Description="Phred probability for MFDN bounds",
                                       Number=1, Type="Float")
HeaderInfoDict["MINAAF"] = HeaderInfoLine(
    ID="MINAAF", Description="Lower bound for AAF given observed frequency a"
    "nd sampling error with confidence described by BINOMP (phred-encoded)",
    Number=1, Type="Float")
HeaderInfoDict["MAXAAF"] = HeaderInfoLine(
    ID="MAXAAF", Description="Upper bound for AAF given observed frequency a"
    "nd sampling error with confidence described by BINOMP (phred-encoded)",
    Number=1, Type="Float")
HeaderInfoDict["BNP"] = HeaderInfoLine(
    ID="BNP", Description="Phred-encoded confidence chosen for calculating "
    "MAXAAF and MINAAF",
    Number=1, Type="Float")
HeaderInfoDict["FFM"] = HeaderInfoLine(
    ID="FFM", Description="Number of reads failed for too few reads in a fami"
    "ly", Number=1, Type="Integer")
HeaderInfoDict["FQC"] = HeaderInfoLine(
    ID="FQC", Description="Number of reads failed for not passing QC ",
    Number=1, Type="Integer")
HeaderInfoDict["FAF"] = HeaderInfoLine(
    ID="FAF", Description=("Number of reads failed for not passing "
                           "Aligned Fraction filter."),
    Number=1, Type="Integer")
HeaderInfoDict["NAF"] = HeaderInfoLine(
    ID="NAF", Description="Number of amplicon-specific failed reads for "
    "pileup in case of mispriming. ",
    Number=1, Type="Integer")
HeaderInfoDict["TND"] = HeaderInfoLine(
    ID="TND", Description="Total number of differences between all reads in a"
    "ll families and the families' respective consensus sequences.",
    Number="A", Type="Integer")
HeaderInfoDict["MNF"] = HeaderInfoLine(
    ID="MNF", Description="Mean number of differences from consensus per read "
    "for all reads supporting allele.",
    Number="A", Type="Float")
HeaderInfoDict["MAXNF"] = HeaderInfoLine(
    ID="MAXNF", Description="Maximum 'NF' tag for a read supporting allele.",
    Number="A", Type="Float")
HeaderInfoDict["NFSD"] = HeaderInfoLine(
    ID="NFSD", Description="Standard deviation for NF tags for a read suppo"
    "rting allele.",
    Number="A", Type="Float")
HeaderInfoDict["NDP"] = HeaderInfoLine(
    ID="NDP", Description="Number of read pairs not included in pileup due to"
    "disagreement on the base call. Large numbers suggest context-specific er"
    "ror modes.", Type="Integer", Number=1)
HeaderInfoDict["MINAF"] = HeaderInfoLine(
    ID="MINAF",
    Description="Minimum aligned fraction to be included in call.",
    Number=1, Type="Float")


"""
This next section contains the dictionaries which hold the
FORMAT Header entries
Valid tags: DP, DPA, DPT
"""

HeaderFormatDict = {}
HeaderFormatDict["DP"] = HeaderFormatLine(
    ID="DP",
    Type="Integer",
    Description=("Merged Read Depth."),
    Number=1)
HeaderFormatDict["DPA"] = HeaderFormatLine(
    ID="DPA",
    Type="Integer",
    Description=("Merged Read Depth for Allele."),
    Number="A")
HeaderFormatDict["DPT"] = HeaderFormatLine(
    ID="DPT",
    Type="Integer",
    Description=("Unmerged Read Depth for Allele."),
    Number="A")


def GetContigHeaderLines(header):
    """
    This program creates the string for the contig lines
    in a VCF from the pysam.AlignmentFile attribute "header".
    """
    if(isinstance(header, dict) is False):
        raise ThisIsMadness("Requires pysam.AlignmentFile header dictionary")
    contigLineList = []
    for contigDict in header['SQ']:
        contigLineList.append(
            HeaderContigLine(contig=contigDict["SN"],
                             length=contigDict["LN"]).__str__())
    return "\n".join(contigLineList)


def GetVCFHeader(fileFormat="default", FILTERTags="default",
                 commandStr="default",
                 reference="default", reference_is_path=False,
                 header="default",
                 INFOTags="default",
                 FORMATTags="default"
                 ):
    HeaderLinesStr = ""
    # fileformat line
    HeaderLinesStr += HeaderFileFormatLine(
        fileformat=fileFormat).__str__() + "\n"
    # FILTER lines
    if(FILTERTags == "default"):
        for key in sorted(HeaderFilterDict.keys()):
            HeaderLinesStr += HeaderFilterDict[key].__str__() + "\n"
    else:
        for filter in FILTERTags.split(","):
            try:
                HeaderLinesStr += HeaderFilterDict[
                    filter.upper()].__str__() + "\n"
            except KeyError:
                pl("Filter {} not found - continuing.".format(filter))
    # INFO lines
    if(INFOTags == "default"):
        for key in sorted(HeaderInfoDict.keys()):
            HeaderLinesStr += HeaderInfoDict[key].__str__() + "\n"
    else:
        for info in INFOTags.split(","):
            try:
                HeaderLinesStr += HeaderInfoDict[
                    info.upper()].__str__() + "\n"
            except KeyError:
                pl("Info {} not found - continuing.".format(info))
    # FORMAT lines
    if(FORMATTags == "default"):
        for key in sorted(HeaderFormatDict.keys()):
            HeaderLinesStr += HeaderFormatDict[key].__str__() + "\n"
    else:
        for format in FORMATTags.split(","):
            try:
                HeaderLinesStr += HeaderFormatDict[
                    format.upper()].__str__() + "\n"
            except KeyError:
                pl("Format {} not found - continuing.".format(format))
    # commandline line
    if(commandStr != "default"):
        HeaderLinesStr += HeaderCommandLine(
            commandStr=commandStr).__str__() + "\n"
    # reference line
    if(reference != "default"):
        HeaderLinesStr += HeaderReferenceLine(
            reference=reference, isfile=reference_is_path).__str__() + "\n"
    # contig lines
    if(header != "default"):
        HeaderLinesStr += GetContigHeaderLines(header) + "\n"
    HeaderLinesStr += "\t".join(["#CHROM", "POS",
                                 "ID", "REF",
                                 "ALT", "QUAL",
                                 "FILTER", "INFO"]) + "\n"
    return HeaderLinesStr
