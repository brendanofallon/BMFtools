/*                                                     fresnl.c
 *
 *     Fresnel integral
 *
 *
 *
 * SYNOPSIS:
 *
 * double x, S, C;
 * void fresnl();
 *
 * fresnl( x, _&S, _&C );
 *
 *
 * DESCRIPTION:
 *
 * Evaluates the Fresnel integrals
 *
 *           x
 *           -
 *          | |
 * C(x) =   |   cos(pi/2 t**2) dt,
 *        | |
 *         -
 *          0
 *
 *           x
 *           -
 *          | |
 * S(x) =   |   sin(pi/2 t**2) dt.
 *        | |
 *         -
 *          0
 *
 *
 * The integrals are evaluated by a power series for x < 1.
 * For x >= 1 auxiliary functions f(x) and g(x) are employed
 * such that
 *
 * C(x) = 0.5 + f(x) sin( pi/2 x**2 ) - g(x) cos( pi/2 x**2 )
 * S(x) = 0.5 - f(x) cos( pi/2 x**2 ) - g(x) sin( pi/2 x**2 )
 *
 *
 *
 * ACCURACY:
 *
 *  Relative error.
 *
 * Arithmetic  function   domain     # trials      peak         rms
 *   IEEE       S(x)      0, 10       10000       2.0e-15     3.2e-16
 *   IEEE       C(x)      0, 10       10000       1.8e-15     3.3e-16
 *   DEC        S(x)      0, 10        6000       2.2e-16     3.9e-17
 *   DEC        C(x)      0, 10        5000       2.3e-16     3.9e-17
 */

/*
 * Cephes Math Library Release 2.1:  January, 1989
 * Copyright 1984, 1987, 1989 by Stephen L. Moshier
 * Direct inquiries to 30 Frost Street, Cambridge, MA 02140
 */

#include "mconf.h"

/* S(x) for small x */
#ifdef UNK
static double sn[6] = {
    -2.99181919401019853726E3,
    7.08840045257738576863E5,
    -6.29741486205862506537E7,
    2.54890880573376359104E9,
    -4.42979518059697779103E10,
    3.18016297876567817986E11,
};

static double sd[6] = {
    /* 1.00000000000000000000E0, */
    2.81376268889994315696E2,
    4.55847810806532581675E4,
    5.17343888770096400730E6,
    4.19320245898111231129E8,
    2.24411795645340920940E10,
    6.07366389490084639049E11,
};
#endif
#ifdef DEC
static unsigned short sn[24] = {
    0143072, 0176433, 0065455, 0127034,
    0045055, 0007200, 0134540, 0026661,
    0146560, 0035061, 0023667, 0127545,
    0050027, 0166503, 0002673, 0153756,
    0151045, 0002721, 0121737, 0102066,
    0051624, 0013177, 0033451, 0021271,
};

static unsigned short sd[24] = {
    /*0040200,0000000,0000000,0000000, */
    0042214, 0130051, 0112070, 0101617,
    0044062, 0010307, 0172346, 0152510,
    0045635, 0160575, 0143200, 0136642,
    0047307, 0171215, 0127457, 0052361,
    0050647, 0031447, 0032621, 0013510,
    0052015, 0064733, 0117362, 0012653,
};
#endif
#ifdef IBMPC
static unsigned short sn[24] = {
    0xb5c3, 0x6d65, 0x5fa3, 0xc0a7,
    0x05b6, 0x172c, 0xa1d0, 0x4125,
    0xf5ed, 0x24f6, 0x0746, 0xc18e,
    0x7afe, 0x60b7, 0xfda8, 0x41e2,
    0xf087, 0x347b, 0xa0ba, 0xc224,
    0x2457, 0xe6e5, 0x82cf, 0x4252,
};

static unsigned short sd[24] = {
    /*0x0000,0x0000,0x0000,0x3ff0, */
    0x1072, 0x3287, 0x9605, 0x4071,
    0xdaa9, 0xfe9c, 0x4218, 0x40e6,
    0x17b4, 0xb8d0, 0xbc2f, 0x4153,
    0xea9e, 0xb5e5, 0xfe51, 0x41b8,
    0x22e9, 0xe6b2, 0xe664, 0x4214,
    0x42b5, 0x73de, 0xad3b, 0x4261,
};
#endif
#ifdef MIEEE
static unsigned short sn[24] = {
    0xc0a7, 0x5fa3, 0x6d65, 0xb5c3,
    0x4125, 0xa1d0, 0x172c, 0x05b6,
    0xc18e, 0x0746, 0x24f6, 0xf5ed,
    0x41e2, 0xfda8, 0x60b7, 0x7afe,
    0xc224, 0xa0ba, 0x347b, 0xf087,
    0x4252, 0x82cf, 0xe6e5, 0x2457,
};

static unsigned short sd[24] = {
    /*0x3ff0,0x0000,0x0000,0x0000, */
    0x4071, 0x9605, 0x3287, 0x1072,
    0x40e6, 0x4218, 0xfe9c, 0xdaa9,
    0x4153, 0xbc2f, 0xb8d0, 0x17b4,
    0x41b8, 0xfe51, 0xb5e5, 0xea9e,
    0x4214, 0xe664, 0xe6b2, 0x22e9,
    0x4261, 0xad3b, 0x73de, 0x42b5,
};
#endif

/* C(x) for small x */
#ifdef UNK
static double cn[6] = {
    -4.98843114573573548651E-8,
    9.50428062829859605134E-6,
    -6.45191435683965050962E-4,
    1.88843319396703850064E-2,
    -2.05525900955013891793E-1,
    9.99999999999999998822E-1,
};

static double cd[7] = {
    3.99982968972495980367E-12,
    9.15439215774657478799E-10,
    1.25001862479598821474E-7,
    1.22262789024179030997E-5,
    8.68029542941784300606E-4,
    4.12142090722199792936E-2,
    1.00000000000000000118E0,
};
#endif
#ifdef DEC
static unsigned short cn[24] = {
    0132126, 0040141, 0063733, 0013231,
    0034037, 0072223, 0010200, 0075637,
    0135451, 0021020, 0073264, 0036057,
    0036632, 0131520, 0101316, 0060233,
    0137522, 0072541, 0136124, 0132202,
    0040200, 0000000, 0000000, 0000000,
};

static unsigned short cd[28] = {
    0026614, 0135503, 0051776, 0032631,
    0030573, 0121116, 0154033, 0126712,
    0032406, 0034100, 0012442, 0106212,
    0034115, 0017567, 0150520, 0164623,
    0035543, 0106171, 0177336, 0146351,
    0037050, 0150073, 0000607, 0171635,
    0040200, 0000000, 0000000, 0000000,
};
#endif
#ifdef IBMPC
static unsigned short cn[24] = {
    0x62d3, 0x2cfb, 0xc80c, 0xbe6a,
    0x0f74, 0x6210, 0xee92, 0x3ee3,
    0x8786, 0x0ed6, 0x2442, 0xbf45,
    0xcc13, 0x1059, 0x566a, 0x3f93,
    0x9690, 0x378a, 0x4eac, 0xbfca,
    0x0000, 0x0000, 0x0000, 0x3ff0,
};

static unsigned short cd[28] = {
    0xc6b3, 0x6a7f, 0x9768, 0x3d91,
    0x75b9, 0xdb03, 0x7449, 0x3e0f,
    0x5191, 0x02a4, 0xc708, 0x3e80,
    0x1d32, 0xfa2a, 0xa3ee, 0x3ee9,
    0xd99d, 0x3fdb, 0x718f, 0x3f4c,
    0xfe74, 0x6030, 0x1a07, 0x3fa5,
    0x0000, 0x0000, 0x0000, 0x3ff0,
};
#endif
#ifdef MIEEE
static unsigned short cn[24] = {
    0xbe6a, 0xc80c, 0x2cfb, 0x62d3,
    0x3ee3, 0xee92, 0x6210, 0x0f74,
    0xbf45, 0x2442, 0x0ed6, 0x8786,
    0x3f93, 0x566a, 0x1059, 0xcc13,
    0xbfca, 0x4eac, 0x378a, 0x9690,
    0x3ff0, 0x0000, 0x0000, 0x0000,
};

static unsigned short cd[28] = {
    0x3d91, 0x9768, 0x6a7f, 0xc6b3,
    0x3e0f, 0x7449, 0xdb03, 0x75b9,
    0x3e80, 0xc708, 0x02a4, 0x5191,
    0x3ee9, 0xa3ee, 0xfa2a, 0x1d32,
    0x3f4c, 0x718f, 0x3fdb, 0xd99d,
    0x3fa5, 0x1a07, 0x6030, 0xfe74,
    0x3ff0, 0x0000, 0x0000, 0x0000,
};
#endif

/* Auxiliary function f(x) */
#ifdef UNK
static double fn[10] = {
    4.21543555043677546506E-1,
    1.43407919780758885261E-1,
    1.15220955073585758835E-2,
    3.45017939782574027900E-4,
    4.63613749287867322088E-6,
    3.05568983790257605827E-8,
    1.02304514164907233465E-10,
    1.72010743268161828879E-13,
    1.34283276233062758925E-16,
    3.76329711269987889006E-20,
};

static double fd[10] = {
    /*  1.00000000000000000000E0, */
    7.51586398353378947175E-1,
    1.16888925859191382142E-1,
    6.44051526508858611005E-3,
    1.55934409164153020873E-4,
    1.84627567348930545870E-6,
    1.12699224763999035261E-8,
    3.60140029589371370404E-11,
    5.88754533621578410010E-14,
    4.52001434074129701496E-17,
    1.25443237090011264384E-20,
};
#endif
#ifdef DEC
static unsigned short fn[40] = {
    0037727, 0152216, 0106601, 0016214,
    0037422, 0154606, 0112710, 0071355,
    0036474, 0143453, 0154253, 0166545,
    0035264, 0161606, 0022250, 0073743,
    0033633, 0110036, 0024653, 0136246,
    0032003, 0036652, 0041164, 0036413,
    0027740, 0174122, 0046305, 0036726,
    0025501, 0125270, 0121317, 0167667,
    0023032, 0150555, 0076175, 0047443,
    0020061, 0133570, 0070130, 0027657,
};

static unsigned short fd[40] = {
    /*0040200,0000000,0000000,0000000, */
    0040100, 0063767, 0054413, 0151452,
    0037357, 0061566, 0007243, 0065754,
    0036323, 0005365, 0033552, 0133625,
    0035043, 0101123, 0000275, 0165402,
    0033367, 0146614, 0110623, 0023647,
    0031501, 0116644, 0125222, 0144263,
    0027436, 0062051, 0117235, 0001411,
    0025204, 0111543, 0056370, 0036201,
    0022520, 0071351, 0015227, 0122144,
    0017554, 0172240, 0112713, 0005006,
};
#endif
#ifdef IBMPC
static unsigned short fn[40] = {
    0x2391, 0xd1b0, 0xfa91, 0x3fda,
    0x0e5e, 0xd2b9, 0x5b30, 0x3fc2,
    0x7dad, 0x7b15, 0x98e5, 0x3f87,
    0x0efc, 0xc495, 0x9c70, 0x3f36,
    0x7795, 0xc535, 0x7203, 0x3ed3,
    0x87a1, 0x484e, 0x67b5, 0x3e60,
    0xa7bb, 0x4998, 0x1f0a, 0x3ddc,
    0xfdf7, 0x1459, 0x3557, 0x3d48,
    0xa9e4, 0xaf8f, 0x5a2d, 0x3ca3,
    0x05f6, 0x0e0b, 0x36ef, 0x3be6,
};

static unsigned short fd[40] = {
    /*0x0000,0x0000,0x0000,0x3ff0, */
    0x7a65, 0xeb21, 0x0cfe, 0x3fe8,
    0x6d7d, 0xc1d4, 0xec6e, 0x3fbd,
    0x56f3, 0xa6ed, 0x615e, 0x3f7a,
    0xbd60, 0x6017, 0x704a, 0x3f24,
    0x64f5, 0x9232, 0xf9b1, 0x3ebe,
    0x5916, 0x9552, 0x33b4, 0x3e48,
    0xa061, 0x33d3, 0xcc85, 0x3dc3,
    0x0790, 0x6b9f, 0x926c, 0x3d30,
    0xf48d, 0x2352, 0x0e5d, 0x3c8a,
    0x6141, 0x12b9, 0x9e94, 0x3bcd,
};
#endif
#ifdef MIEEE
static unsigned short fn[40] = {
    0x3fda, 0xfa91, 0xd1b0, 0x2391,
    0x3fc2, 0x5b30, 0xd2b9, 0x0e5e,
    0x3f87, 0x98e5, 0x7b15, 0x7dad,
    0x3f36, 0x9c70, 0xc495, 0x0efc,
    0x3ed3, 0x7203, 0xc535, 0x7795,
    0x3e60, 0x67b5, 0x484e, 0x87a1,
    0x3ddc, 0x1f0a, 0x4998, 0xa7bb,
    0x3d48, 0x3557, 0x1459, 0xfdf7,
    0x3ca3, 0x5a2d, 0xaf8f, 0xa9e4,
    0x3be6, 0x36ef, 0x0e0b, 0x05f6,
};

static unsigned short fd[40] = {
    /*0x3ff0,0x0000,0x0000,0x0000, */
    0x3fe8, 0x0cfe, 0xeb21, 0x7a65,
    0x3fbd, 0xec6e, 0xc1d4, 0x6d7d,
    0x3f7a, 0x615e, 0xa6ed, 0x56f3,
    0x3f24, 0x704a, 0x6017, 0xbd60,
    0x3ebe, 0xf9b1, 0x9232, 0x64f5,
    0x3e48, 0x33b4, 0x9552, 0x5916,
    0x3dc3, 0xcc85, 0x33d3, 0xa061,
    0x3d30, 0x926c, 0x6b9f, 0x0790,
    0x3c8a, 0x0e5d, 0x2352, 0xf48d,
    0x3bcd, 0x9e94, 0x12b9, 0x6141,
};
#endif


/* Auxiliary function g(x) */
#ifdef UNK
static double gn[11] = {
    5.04442073643383265887E-1,
    1.97102833525523411709E-1,
    1.87648584092575249293E-2,
    6.84079380915393090172E-4,
    1.15138826111884280931E-5,
    9.82852443688422223854E-8,
    4.45344415861750144738E-10,
    1.08268041139020870318E-12,
    1.37555460633261799868E-15,
    8.36354435630677421531E-19,
    1.86958710162783235106E-22,
};

static double gd[11] = {
    /*  1.00000000000000000000E0, */
    1.47495759925128324529E0,
    3.37748989120019970451E-1,
    2.53603741420338795122E-2,
    8.14679107184306179049E-4,
    1.27545075667729118702E-5,
    1.04314589657571990585E-7,
    4.60680728146520428211E-10,
    1.10273215066240270757E-12,
    1.38796531259578871258E-15,
    8.39158816283118707363E-19,
    1.86958710162783236342E-22,
};
#endif
#ifdef DEC
static unsigned short gn[44] = {
    0040001, 0021435, 0120406, 0053123,
    0037511, 0152523, 0037703, 0122011,
    0036631, 0134302, 0122721, 0110235,
    0035463, 0051712, 0043215, 0114732,
    0034101, 0025677, 0147725, 0057630,
    0032323, 0010342, 0067523, 0002206,
    0030364, 0152247, 0110007, 0054107,
    0026230, 0057654, 0035464, 0047124,
    0023706, 0036401, 0167705, 0045440,
    0021166, 0154447, 0105632, 0142461,
    0016142, 0002353, 0011175, 0170530,
};

static unsigned short gd[44] = {
    /*0040200,0000000,0000000,0000000, */
    0040274, 0145551, 0016742, 0127005,
    0037654, 0166557, 0076416, 0015165,
    0036717, 0140217, 0030675, 0050111,
    0035525, 0110060, 0076405, 0070502,
    0034125, 0176061, 0060120, 0031730,
    0032340, 0001615, 0054343, 0120501,
    0030375, 0041414, 0070747, 0107060,
    0026233, 0031034, 0160757, 0074526,
    0023710, 0003341, 0137100, 0144664,
    0021167, 0126414, 0023774, 0015435,
    0016142, 0002353, 0011175, 0170530,
};
#endif
#ifdef IBMPC
static unsigned short gn[44] = {
    0xcaca, 0xb420, 0x2463, 0x3fe0,
    0x7481, 0x67f8, 0x3aaa, 0x3fc9,
    0x3214, 0x54ba, 0x3718, 0x3f93,
    0xb33b, 0x48d1, 0x6a79, 0x3f46,
    0xabf3, 0xf9fa, 0x2577, 0x3ee8,
    0x6091, 0x4dea, 0x621c, 0x3e7a,
    0xeb09, 0xf200, 0x9a94, 0x3dfe,
    0x89cb, 0x8766, 0x0bf5, 0x3d73,
    0xa964, 0x3df8, 0xc7a0, 0x3cd8,
    0x58a6, 0xf173, 0xdb24, 0x3c2e,
    0xbe2b, 0x624f, 0x409d, 0x3b6c,
};

static unsigned short gd[44] = {
    /*0x0000,0x0000,0x0000,0x3ff0, */
    0x55c1, 0x23bc, 0x996d, 0x3ff7,
    0xc34f, 0xefa1, 0x9dad, 0x3fd5,
    0xaa09, 0xe637, 0xf811, 0x3f99,
    0xae28, 0x0fa0, 0xb206, 0x3f4a,
    0x067b, 0x2c0a, 0xbf86, 0x3eea,
    0x7428, 0xab1c, 0x0071, 0x3e7c,
    0xf1c6, 0x8e3c, 0xa861, 0x3dff,
    0xef2b, 0x9c3d, 0x6643, 0x3d73,
    0x1936, 0x37c8, 0x00dc, 0x3cd9,
    0x8364, 0x84ff, 0xf5a1, 0x3c2e,
    0xbe2b, 0x624f, 0x409d, 0x3b6c,
};
#endif
#ifdef MIEEE
static unsigned short gn[44] = {
    0x3fe0, 0x2463, 0xb420, 0xcaca,
    0x3fc9, 0x3aaa, 0x67f8, 0x7481,
    0x3f93, 0x3718, 0x54ba, 0x3214,
    0x3f46, 0x6a79, 0x48d1, 0xb33b,
    0x3ee8, 0x2577, 0xf9fa, 0xabf3,
    0x3e7a, 0x621c, 0x4dea, 0x6091,
    0x3dfe, 0x9a94, 0xf200, 0xeb09,
    0x3d73, 0x0bf5, 0x8766, 0x89cb,
    0x3cd8, 0xc7a0, 0x3df8, 0xa964,
    0x3c2e, 0xdb24, 0xf173, 0x58a6,
    0x3b6c, 0x409d, 0x624f, 0xbe2b,
};

static unsigned short gd[44] = {
    /*0x3ff0,0x0000,0x0000,0x0000, */
    0x3ff7, 0x996d, 0x23bc, 0x55c1,
    0x3fd5, 0x9dad, 0xefa1, 0xc34f,
    0x3f99, 0xf811, 0xe637, 0xaa09,
    0x3f4a, 0xb206, 0x0fa0, 0xae28,
    0x3eea, 0xbf86, 0x2c0a, 0x067b,
    0x3e7c, 0x0071, 0xab1c, 0x7428,
    0x3dff, 0xa861, 0x8e3c, 0xf1c6,
    0x3d73, 0x6643, 0x9c3d, 0xef2b,
    0x3cd9, 0x00dc, 0x37c8, 0x1936,
    0x3c2e, 0xf5a1, 0x84ff, 0x8364,
    0x3b6c, 0x409d, 0x624f, 0xbe2b,
};
#endif

extern double MACHEP;

int fresnl(xxa, ssa, cca)
double xxa, *ssa, *cca;
{
    double f, g, cc, ss, c, s, t, u;
    double x, x2;

    x = fabs(xxa);
    x2 = x * x;
    if (x2 < 2.5625) {
    t = x2 * x2;
    ss = x * x2 * polevl(t, sn, 5) / p1evl(t, sd, 6);
    cc = x * polevl(t, cn, 5) / polevl(t, cd, 6);
    goto done;
    }

    if (x > 36974.0) {
        /*
         * http://functions.wolfram.com/GammaBetaErf/FresnelC/06/02/
         * http://functions.wolfram.com/GammaBetaErf/FresnelS/06/02/
         */
    cc = 0.5 + 1/(NPY_PI*x) * sin(NPY_PI*x*x/2);
    ss = 0.5 - 1/(NPY_PI*x) * cos(NPY_PI*x*x/2);
    goto done;
    }


    /*             Asymptotic power series auxiliary functions
     *             for large argument
     */
    x2 = x * x;
    t = NPY_PI * x2;
    u = 1.0 / (t * t);
    t = 1.0 / t;
    f = 1.0 - u * polevl(u, fn, 9) / p1evl(u, fd, 10);
    g = t * polevl(u, gn, 10) / p1evl(u, gd, 11);

    t = NPY_PI_2 * x2;
    c = cos(t);
    s = sin(t);
    t = NPY_PI * x;
    cc = 0.5 + (f * s - g * c) / t;
    ss = 0.5 - (f * c + g * s) / t;

  done:
    if (xxa < 0.0) {
    cc = -cc;
    ss = -ss;
    }

    *cca = cc;
    *ssa = ss;
    return (0);
}
