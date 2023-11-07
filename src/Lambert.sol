// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {toWadUnsafe, wadExp, wadLn, unsafeWadMul, unsafeWadDiv} from "solmate/utils/SignedWadMath.sol";

/// @notice Numerical approximation for principal branch of [Lambert W
/// function](https://en.wikipedia.org/wiki/Lambert_W_function)
/// @dev Only supports the [1/e, 3+1/e] and [3+1/e, inf] interval
/// @dev Approximate [1/e, 3+1/e] with a lookup table weighted average and [3+1/e, inf] with ln(x) + ln(ln(x)) +
/// ln(ln(x))/ln(x)
contract Lambert {
    int256 internal constant E_WAD = 2718281828459045235;
    int256 internal constant LOWER_BOUND_WAD = 367879441171442322; // 1/e
    int256 internal constant MID_BOUND_WAD = 3367879441171442322; // 3 + 1/e

    int256 internal constant PRECISION_SLOTS = 128;
    int256[129] internal lambertArray;

    constructor() {
        initLambertArray();
    }

    /// @notice Approximates W0(x) where x is a wad
    function W0(int256 xWad) external view returns (int256) {
        require(LOWER_BOUND_WAD <= xWad, "must be > 1/e");
        if (xWad <= MID_BOUND_WAD) {
            int256 range = MID_BOUND_WAD - LOWER_BOUND_WAD;
            // Use weighted average of lookup table
            // Slot number is slotCount * (x - a) / (b - a), we want integer rounding here
            int256 slotIndex = (PRECISION_SLOTS * (xWad - LOWER_BOUND_WAD)) / range;
            int256 a = LOWER_BOUND_WAD + slotIndex * range / PRECISION_SLOTS;
            int256 b = a + range / PRECISION_SLOTS;
            // Weighted average is f(a) + w(f(b) - f(a)) = wf(b) + (1-w)f(a) where w = (x-a)/(b-a)
            int256 w = unsafeWadDiv(xWad - a, MID_BOUND_WAD);
            int256 result = unsafeWadMul(w, lambertArray[uint256(slotIndex + 1)])
                + unsafeWadMul(1e18 - w, lambertArray[uint256(slotIndex)]);
            return result;
        } else {
            // Approximate
            int256 log = wadLn(xWad);
            int256 loglog = wadLn(log);
            return log + loglog + unsafeWadDiv(loglog, log);
        }
    }

    function initLambertArray() internal {
        lambertArray[0] = 0;
        lambertArray[1] = 567143290409783840;
        lambertArray[2] = 852605502013725425;
        lambertArray[3] = 1049908894964040051;
        lambertArray[4] = 1202167873197042880;
        lambertArray[5] = 1326724665242200230;
        lambertArray[6] = 1432404775898300286;
        lambertArray[7] = 1524345204984144386;
        lambertArray[8] = 1605811996320177570;
        lambertArray[9] = 1679016419785598124;
        lambertArray[10] = 1745528002740699414;
        lambertArray[11] = 1806502575505666064;
        lambertArray[12] = 1862816864432357944;
        lambertArray[13] = 1915152239536356493;
        lambertArray[14] = 1964049113249477729;
        lambertArray[15] = 2009943559350565678;
        lambertArray[16] = 2053192717462648531;
        lambertArray[17] = 2094092878166321725;
        lambertArray[18] = 2132892648536085733;
        lambertArray[19] = 2169802725605733063;
        lambertArray[20] = 2205003278024059821;
        lambertArray[21] = 2238649607458893520;
        lambertArray[22] = 2270876550711971031;
        lambertArray[23] = 2301801945269356331;
        lambertArray[24] = 2331529388280118908;
        lambertArray[25] = 2360150455522664004;
        lambertArray[26] = 2387746502752277067;
        lambertArray[27] = 2414390140573880128;
        lambertArray[28] = 2440146451545914363;
        lambertArray[29] = 2465074001891232935;
        lambertArray[30] = 2489225688157678196;
        lambertArray[31] = 2512649450201651646;
        lambertArray[32] = 2535388875110911044;
        lambertArray[33] = 2557483711541749027;
        lambertArray[34] = 2578970309998022792;
        lambertArray[35] = 2599882001521901298;
        lambertArray[36] = 2620249424878907885;
        lambertArray[37] = 2640100810441690093;
        lambertArray[38] = 2659462227488875286;
        lambertArray[39] = 2678357800448373016;
        lambertArray[40] = 2696809898661708171;
        lambertArray[41] = 2714839303476542121;
        lambertArray[42] = 2732465355849723831;
        lambertArray[43] = 2749706087133044985;
        lambertArray[44] = 2766578335295223123;
        lambertArray[45] = 2783097848488405468;
        lambertArray[46] = 2799279377581496142;
        lambertArray[47] = 2815136759044622128;
        lambertArray[48] = 2830682989370233660;
        lambertArray[49] = 2845930292049501986;
        lambertArray[50] = 2860890177982210680;
        lambertArray[51] = 2875573500079602773;
        lambertArray[52] = 2889990502718916776;
        lambertArray[53] = 2904150866622654092;
        lambertArray[54] = 2918063749662424655;
        lambertArray[55] = 2931737824024537531;
        lambertArray[56] = 2945181310120670748;
        lambertArray[57] = 2958402007580566373;
        lambertArray[58] = 2971407323623616925;
        lambertArray[59] = 2984204299071516076;
        lambertArray[60] = 2996799632233991595;
        lambertArray[61] = 3009199700873411043;
        lambertArray[62] = 3021410582431138803;
        lambertArray[63] = 3033438072678511510;
        lambertArray[64] = 3045287702937726326;
        lambertArray[65] = 3056964756002523931;
        lambertArray[66] = 3068474280874967874;
        lambertArray[67] = 3079821106422639065;
        lambertArray[68] = 3091009854049979744;
        lambertArray[69] = 3102044949468157231;
        lambertArray[70] = 3112930633639477751;
        lambertArray[71] = 3123670972965013615;
        lambertArray[72] = 3134269868777511459;
        lambertArray[73] = 3144731066195779690;
        lambertArray[74] = 3155058162391525478;
        lambertArray[75] = 3165254614314898518;
        lambertArray[76] = 3175323745920822560;
        lambertArray[77] = 3185268754934400981;
        lambertArray[78] = 3195092719190305797;
        lambertArray[79] = 3204798602578010858;
        lambertArray[80] = 3214389260621969502;
        lambertArray[81] = 3223867445723367364;
        lambertArray[82] = 3233235812087832617;
        lambertArray[83] = 3242496920361459978;
        lambertArray[84] = 3251653241995665855;
        lambertArray[85] = 3260707163359727989;
        lambertArray[86] = 3269660989618341951;
        lambertArray[87] = 3278516948390160390;
        lambertArray[88] = 3287277193202023717;
        lambertArray[89] = 3295943806752444249;
        lambertArray[90] = 3304518803996878251;
        lambertArray[91] = 3313004135066350386;
        lambertArray[92] = 3321401688030150456;
        lambertArray[93] = 3329713291512499840;
        lambertArray[94] = 3337940717172378946;
        lambertArray[95] = 3346085682055033317;
        lambertArray[96] = 3354149850823047174;
        lambertArray[97] = 3362134837874341642;
        lambertArray[98] = 3370042209353906415;
        lambertArray[99] = 3377873485065618020;
        lambertArray[100] = 3385630140290050161;
        lambertArray[101] = 3393313607513777530;
        lambertArray[102] = 3400925278075309421;
        lambertArray[103] = 3408466503732434205;
        lambertArray[104] = 3415938598155447536;
        lambertArray[105] = 3423342838350432960;
        lambertArray[106] = 3430680466016503782;
        lambertArray[107] = 3437952688840654858;
        lambertArray[108] = 3445160681733636210;
        lambertArray[109] = 3452305588010054826;
        lambertArray[110] = 3459388520515700449;
        lambertArray[111] = 3466410562704908216;
        lambertArray[112] = 3473372769670597826;
        lambertArray[113] = 3480276169129463693;
        lambertArray[114] = 3487121762364648880;
        lambertArray[115] = 3493910525128082423;
        lambertArray[116] = 3500643408504545917;
        lambertArray[117] = 3507321339739395416;
        lambertArray[118] = 3513945223031770038;
        lambertArray[119] = 3520515940294993928;
        lambertArray[120] = 3527034351885797392;
        lambertArray[121] = 3533501297303879518;
        lambertArray[122] = 3539917595863243616;
        lambertArray[123] = 3546284047336678569;
        lambertArray[124] = 3552601432574650442;
        lambertArray[125] = 3558870514099828686;
        lambertArray[126] = 3565092036678385146;
        lambertArray[127] = 3571266727869151225;
        lambertArray[128] = 3577395298551653280;
    }
}
