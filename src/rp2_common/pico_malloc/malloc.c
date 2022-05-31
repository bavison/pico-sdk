/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#if defined __ICCARM__

/* Used when you select "No-free heap" in Project > Options... > General options > Library options 2 */
#define PREFIX __no_free_
#include "malloc.inc.c"
#undef PREFIX
/* Used when you select "Basic heap" in Project > Options... > General options > Library options 2 */
#define PREFIX __basic_
#include "malloc.inc.c"
#undef PREFIX
/* Used when you select "Advanced heap" in Project > Options... > General options > Library options 2 */
#define PREFIX __iar_dl
#include "malloc.inc.c"
#undef PREFIX

#else

/* Assume the runtime library only contains one heap implementation, so just
 * include malloc.inc.c */
#define PREFIX
#include "malloc.inc.c"
#undef PREFIX

#endif
