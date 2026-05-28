/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

INIT macro
 cdp p4,#0,c0,c0,c0,#0
 endm
ADD0 macro
 cdp p4,#0,c0,c0,c1,#0
 endm
ADD1 macro
 cdp p4,#1,c0,c0,c1,#0
 endm
SUB1 macro
 cdp p4,#1,c0,c0,c1,#1
 endm
SQR0 macro
 cdp p4,#2,c0,c0,c1,#0
 endm
NORM macro
 cdp p4,#8,c0,c0,c2,#0
 endm
NRDF macro
 cdp p4,#8,c0,c0,c2,#1
 endm
NRDD macro
 cdp p4,#8,c0,c0,c0,#1
 endm
NTDC macro
 cdp p4,#8,c0,c0,c0,#2
 endm
NRDC macro
 cdp p4,#8,c0,c0,c0,#3
 endm
WXMD macro rl, rh
 mcrr p4,#0,rl,rh,c0
 endm
WYMD macro rl, rh
 mcrr p4,#0,rl,rh,c1
 endm
WEFD macro rl, rh
 mcrr p4,#0,rl,rh,c2
 endm
WXUP macro rl, rh
 mcrr p4,#1,rl,rh,c0
 endm
WYUP macro rl, rh
 mcrr p4,#1,rl,rh,c1
 endm
WXYU macro rl, rh
 mcrr p4,#1,rl,rh,c2
 endm
WXMS macro rl, rh
 mcrr p4,#2,rl,rh,c0
 endm
WXMO macro rl, rh
 mcrr p4,#3,rl,rh,c0
 endm
WXDD macro rl, rh
 mcrr p4,#4,rl,rh,c0
 endm
WXDQ macro rl, rh
 mcrr p4,#5,rl,rh,c0
 endm
WXUC macro rl, rh
 mcrr p4,#6,rl,rh,c0
 endm
WXIC macro rl, rh
 mcrr p4,#7,rl,rh,c0
 endm
WXDC macro rl, rh
 mcrr p4,#8,rl,rh,c0
 endm
WXFC macro rl, rh
 mcrr p4,#9,rl,rh,c2
 endm
WXFM macro rl, rh
 mcrr p4,#10,rl,rh,c0
 endm
WXFD macro rl, rh
 mcrr p4,#11,rl,rh,c0
 endm
WXFQ macro rl, rh
 mcrr p4,#12,rl,rh,c0
 endm
RXVD macro rt
 mrc p4,#0,rt,c0,c0,#0
 endm
RCMP macro rt
 mrc p4,#0,rt,c0,c0,#1
 endm
RDFA macro rt
 mrc p4,#0,rt,c0,c2,#0
 endm
RDFS macro rt
 mrc p4,#0,rt,c0,c2,#1
 endm
RDFM macro rt
 mrc p4,#0,rt,c0,c2,#2
 endm
RDFD macro rt
 mrc p4,#0,rt,c0,c2,#3
 endm
RDFQ macro rt
 mrc p4,#0,rt,c0,c2,#4
 endm
RDFG macro rt
 mrc p4,#0,rt,c0,c2,#5
 endm
RDIC macro rt
 mrc p4,#0,rt,c0,c3,#0
 endm
RDUC macro rt
 mrc p4,#0,rt,c0,c3,#1
 endm
RXMD macro rl, rh
 mrrc p4,#0,rl,rh,c8
 endm
RYMD macro rl, rh
 mrrc p4,#0,rl,rh,c9
 endm
REFD macro rl, rh
 mrrc p4,#0,rl,rh,c10
 endm
RXMS macro rl, rh, s
 mrrc p4,#s,rl,rh,c4
 endm
RYMS macro rl, rh, s
 mrrc p4,#s,rl,rh,c5
 endm
RXYH macro rl, rh
 mrrc p4,#1,rl,rh,c1
 endm
RYMR macro rl, rh
 mrrc p4,#2,rl,rh,c1
 endm
RXMQ macro rl, rh
 mrrc p4,#4,rl,rh,c1
 endm
RDDA macro rl, rh
 mrrc p4,#1,rl,rh,c0
 endm
RDDS macro rl, rh
 mrrc p4,#3,rl,rh,c0
 endm
RDDM macro rl, rh
 mrrc p4,#5,rl,rh,c0
 endm
RDDD macro rl, rh
 mrrc p4,#7,rl,rh,c0
 endm
RDDQ macro rl, rh
 mrrc p4,#9,rl,rh,c0
 endm
RDDG macro rl, rh
 mrrc p4,#11,rl,rh,c0
 endm
PXVD macro rt
 mrc2 p4,#0,rt,c0,c0,#0
 endm
PCMP macro rt
 mrc2 p4,#0,rt,c0,c0,#1
 endm
PDFA macro rt
 mrc2 p4,#0,rt,c0,c2,#0
 endm
PDFS macro rt
 mrc2 p4,#0,rt,c0,c2,#1
 endm
PDFM macro rt
 mrc2 p4,#0,rt,c0,c2,#2
 endm
PDFD macro rt
 mrc2 p4,#0,rt,c0,c2,#3
 endm
PDFQ macro rt
 mrc2 p4,#0,rt,c0,c2,#4
 endm
PDFG macro rt
 mrc2 p4,#0,rt,c0,c2,#5
 endm
PDIC macro rt
 mrc2 p4,#0,rt,c0,c3,#0
 endm
PDUC macro rt
 mrc2 p4,#0,rt,c0,c3,#1
 endm
PXMD macro rl, rh
 mrrc2 p4,#0,rl,rh,c8
 endm
PYMD macro rl, rh
 mrrc2 p4,#0,rl,rh,c9
 endm
PEFD macro rl, rh
 mrrc2 p4,#0,rl,rh,c10
 endm
PXMS macro rl, rh, s
 mrrc2 p4,#s,rl,rh,c4
 endm
PYMS macro rl, rh, s
 mrrc2 p4,#s,rl,rh,c5
 endm
PXYH macro rl, rh
 mrrc2 p4,#1,rl,rh,c1
 endm
PYMR macro rl, rh
 mrrc2 p4,#2,rl,rh,c1
 endm
PXMQ macro rl, rh
 mrrc2 p4,#4,rl,rh,c1
 endm
PDDA macro rl, rh
 mrrc2 p4,#1,rl,rh,c0
 endm
PDDS macro rl, rh
 mrrc2 p4,#3,rl,rh,c0
 endm
PDDM macro rl, rh
 mrrc2 p4,#5,rl,rh,c0
 endm
PDDD macro rl, rh
 mrrc2 p4,#7,rl,rh,c0
 endm
PDDQ macro rl, rh
 mrrc2 p4,#9,rl,rh,c0
 endm
PDDG macro rl, rh
 mrrc2 p4,#11,rl,rh,c0
 endm

