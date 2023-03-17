#!/usr/bin/env python3
#
# Copyright (c) 2023 Raspberry Pi Ltd.
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Script to parse an IAR workspace (.EWW) file and perform a batch build.
# Uses two environment variables:
#   IARBUILD_PATH  = path to directory holding IAR tools binaries
#   IARBUILD_OPTS  = additional options to pass to iarbuild tool

import os
import re
import subprocess
import sys
import xmltodict

if len(sys.argv) != 3:
    print(f'Syntax: {sys.argv[0]} <path to workspace file> <batch name>',
          file=sys.stderr)
    exit(1)

with open(sys.argv[1]) as f:
    w = xmltodict.parse(f.read())

    # Create look-up dict from project name to project path
    path = { re.sub('.*\\\\([^\\\\]*).ewp', '\\1', p['path']):
             re.sub('^\\$WS_DIR\\$/', '', re.sub('\\\\', '/', p['path']))
             for p in w['workspace']['project'] }

    # Search for the requested batch
    for b in w['workspace']['batchBuild']['batchDefinition']:
        if b['name'] == sys.argv[2]:
            # Now dispatch each member of the batch to the iarbuild
            for m in b['member']:
                subprocess.run([ f'{os.environ["IARBUILD_PATH"]}/iarbuild',
                                 os.path.dirname(sys.argv[1]) + '/' + path[m["project"]],
                                 '-build',
                                 m["configuration"]
                               ] + os.environ["IARBUILD_OPTS"].split(),
                               check=True)
