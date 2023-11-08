// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {wadLn, unsafeWadMul, unsafeWadDiv} from "solmate/utils/SignedWadMath.sol";

/// @notice Approximated principal branch of [Lambert W function](https://en.wikipedia.org/wiki/Lambert_W_function)
/// @dev Only supports the [1/e, 3+1/e] and [3+1/e, inf] interval
/// @dev Approximate [1/e, 3+1/e] with a lookup table weighted average
/// @dev Approximate and [3+1/e, inf] with ln(x) - ln(ln(x)) + ln(ln(x))/ln(x)
contract Lambert {
    // int256 internal constant E_WAD = 2718281828459045235; // e
    int256 internal constant LOWER_BOUND_WAD = 367879441171442322; // 1/e
    int256 internal constant MID_BOUND_WAD = 3367879441171442322; // 3 + 1/e

    int256 internal constant PRECISION_SLOTS = 128;
    int256[129] internal lambertArray;

    constructor() {
        initLambertArray();
    }

    /// @notice Approximates W0(x) where x is a wad
    function W0(int256 xWad) public view returns (int256) {
        require(LOWER_BOUND_WAD < xWad, "must be > 1/e");
        if (xWad <= MID_BOUND_WAD) {
            int256 range = MID_BOUND_WAD - LOWER_BOUND_WAD;
            int256 slotWidth = range / PRECISION_SLOTS;
            // Use weighted average of lookup table
            // Slot number is slotCount * (x - a) / (b - a), we want integer rounding here
            int256 slotIndex = (PRECISION_SLOTS * (xWad - LOWER_BOUND_WAD)) / range;
            int256 a = LOWER_BOUND_WAD + slotIndex * slotWidth;
            // Weighted average is f(a) + w(f(b) - f(a)) = wf(b) + (1-w)f(a) where w = (x-a)/(b-a)
            int256 w = unsafeWadDiv(xWad - a, slotWidth);
            int256 result = unsafeWadMul(w, lambertArray[uint256(slotIndex + 1)])
                + unsafeWadMul(1e18 - w, lambertArray[uint256(slotIndex)]);
            return result;
        } else {
            // Approximate
            int256 log = wadLn(xWad);
            int256 loglog = wadLn(log);
            return log - loglog + unsafeWadDiv(loglog, log);
        }
    }

    function initLambertArray() internal {
        lambertArray[0] = 278464542761073797;
        lambertArray[1] = 292172712904375409;
        lambertArray[2] = 305555431092177421;
        lambertArray[3] = 318629149736825601;
        lambertArray[4] = 331409057679665886;
        lambertArray[5] = 343909209059935161;
        lambertArray[6] = 356142635944376729;
        lambertArray[7] = 368121447135459079;
        lambertArray[8] = 379856915163428677;
        lambertArray[9] = 391359553133757476;
        lambertArray[10] = 402639182830180964;
        lambertArray[11] = 413704995251618912;
        lambertArray[12] = 424565604578874267;
        lambertArray[13] = 435229096416341055;
        lambertArray[14] = 445703071028916709;
        lambertArray[15] = 455994682190091871;
        lambertArray[16] = 466110672169935236;
        lambertArray[17] = 476057403318360051;
        lambertArray[18] = 485840886637179337;
        lambertArray[19] = 495466807682053367;
        lambertArray[20] = 504940550090895113;
        lambertArray[21] = 514267216997322474;
        lambertArray[22] = 523451650555249004;
        lambertArray[23] = 532498449772820237;
        lambertArray[24] = 541411986829900771;
        lambertArray[25] = 550196422032591226;
        lambertArray[26] = 558855717540319930;
        lambertArray[27] = 567393649985483250;
        lambertArray[28] = 575813822092059002;
        lambertArray[29] = 584119673387799576;
        lambertArray[30] = 592314490094275059;
        lambertArray[31] = 600401414269979283;
        lambertArray[32] = 608383452273753234;
        lambertArray[33] = 616263482608777391;
        lambertArray[34] = 624044263201202654;
        lambertArray[35] = 631728438162032946;
        lambertArray[36] = 639318544076026285;
        lambertArray[37] = 646817015857100830;
        lambertArray[38] = 654226192205905832;
        lambertArray[39] = 661548320701825454;
        lambertArray[40] = 668785562558651736;
        lambertArray[41] = 675939997070453713;
        lambertArray[42] = 683013625771744626;
        lambertArray[43] = 690008376333878015;
        lambertArray[44] = 696926106217652719;
        lambertArray[45] = 703768606100349969;
        lambertArray[46] = 710537603093849057;
        lambertArray[47] = 717234763769043826;
        lambertArray[48] = 723861697000492410;
        lambertArray[49] = 730419956644077550;
        lambertArray[50] = 736911044059391562;
        lambertArray[51] = 743336410487617893;
        lambertArray[52] = 749697459294802693;
        lambertArray[53] = 755995548089636205;
        lambertArray[54] = 762231990724133057;
        lambertArray[55] = 768408059184963688;
        lambertArray[56] = 774524985382581632;
        lambertArray[57] = 780583962844757062;
        lambertArray[58] = 786586148320626566;
        lambertArray[59] = 792532663300919205;
        lambertArray[60] = 798424595459597874;
        lambertArray[61] = 804263000021781194;
        lambertArray[62] = 810048901062455862;
        lambertArray[63] = 815783292740172583;
        lambertArray[64] = 821467140469620660;
        lambertArray[65] = 827101382036708799;
        lambertArray[66] = 832686928659525094;
        lambertArray[67] = 838224665998323348;
        lambertArray[68] = 843715455117467705;
        lambertArray[69] = 849160133402072970;
        lambertArray[70] = 854559515431895012;
        lambertArray[71] = 859914393814860567;
        lambertArray[72] = 865225539982468761;
        lambertArray[73] = 870493704949152902;
        lambertArray[74] = 875719620037561097;
        lambertArray[75] = 880903997571585440;
        lambertArray[76] = 886047531538859845;
        lambertArray[77] = 891150898224339238;
        lambertArray[78] = 896214756816469116;
        lambertArray[79] = 901239749987370664;
        lambertArray[80] = 906226504448373937;
        lambertArray[81] = 911175631482154635;
        lambertArray[82] = 916087727452656209;
        lambertArray[83] = 920963374293908510;
        lambertArray[84] = 925803139978790490;
        lambertArray[85] = 930607578968721594;
        lambertArray[86] = 935377232645214773;
        lambertArray[87] = 940112629724165316;
        lambertArray[88] = 944814286653706370;
        lambertArray[89] = 949482707996410547;
        lambertArray[90] = 954118386796576901;
        lambertArray[91] = 958721804933301169;
        lambertArray[92] = 963293433459989745;
        lambertArray[93] = 967833732930940771;
        lambertArray[94] = 972343153715582553;
        lambertArray[95] = 976822136300931065;
        lambertArray[96] = 981271111582793343;
        lambertArray[97] = 985690501146222142;
        lambertArray[98] = 990080717535694044;
        lambertArray[99] = 994442164515466409;
        lambertArray[100] = 998775237320539411;
        lambertArray[101] = 1003080322898629140;
        lambertArray[102] = 1007357800143540594;
        lambertArray[103] = 1011608040120304475;
        lambertArray[104] = 1015831406282428295;
        lambertArray[105] = 1020028254681592861;
        lambertArray[106] = 1024198934170108544;
        lambertArray[107] = 1028343786596431775;
        lambertArray[108] = 1032463146994028413;
        lambertArray[109] = 1036557343763853112;
        lambertArray[110] = 1040626698850704912;
        lambertArray[111] = 1044671527913707987;
        lambertArray[112] = 1048692140491147340;
        lambertArray[113] = 1052688840159887729;
        lambertArray[114] = 1056661924689589638;
        lambertArray[115] = 1060611686191922587;
        lambertArray[116] = 1064538411264973616;
        lambertArray[117] = 1068442381133036578;
        lambertArray[118] = 1072323871781957871;
        lambertArray[119] = 1076183154090209149;
        lambertArray[120] = 1080020493955848426;
        lambertArray[121] = 1083836152419526133;
        lambertArray[122] = 1087630385783681541;
        lambertArray[123] = 1091403445728072796;
        lambertArray[124] = 1095155579421774661;
        lambertArray[125] = 1098887029631776757;
        lambertArray[126] = 1102598034828299989;
        lambertArray[127] = 1106288829286957931;
        lambertArray[128] = 1109959643187871325;
    }
}
