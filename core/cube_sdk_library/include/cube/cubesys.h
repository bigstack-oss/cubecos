// CUBE SDK

#ifndef CUBE_SYS_H
#define CUBE_SYS_H

/**
 *  This file contains the functions that check for cube cluster state.
 */

#ifdef __cplusplus
extern "C" {
#endif

enum cuberole {
    R_UNDEF = 0x0,
    R_CONTROL = 0x1,
    R_COMPUTE = 0x2,
    R_STORAGE = 0x4,
    R_CTRL_NOT_EDGE = 0x8,
    R_CORE = 0x10,
    R_CC = R_CONTROL | R_COMPUTE | R_STORAGE,
    R_ALL = R_CC
};

enum bootlvl {
    BLVL_BS = 0,
    BLVL_STD = 1,
    BLVL_DONE = 2
};

int CubeSysCommitAll(void);
int CubeBootLevel(void);
int CubeHasRole(int);

#ifdef __cplusplus
} /* end extern "C" */
#endif

#endif /* endif CUBE_SYS_H */

