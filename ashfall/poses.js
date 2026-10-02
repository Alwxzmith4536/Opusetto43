// poses.js — pose library. Local space: pelvis at origin, facing +x, y up.
// sab = blade angle (deg, 0 = forward, 90 = up, 180 = back, -90 = down). h1 = saber hand, h2 = off hand (two:1 snaps it to the hilt).
(function (root) {
'use strict';
const { defPose } = root.CORE;

defPose('idle',     { tor: 2, h1x: 12, h1y: -24, h2x: -8, h2y: -30, f1x: 9, f1y: -86, f2x: -9, f2y: -86, sab: -85 });
defPose('idleLook', { tor: -3, hd: -8, h1x: 10, h1y: -26, h2x: -6, h2y: -30, f1x: 12, f1y: -85, f2x: -10, f2y: -86, sab: -85 });
defPose('walkP',    { tor: 8, walk: 1, h1x: 14, h1y: -22, sab: -85 });
defPose('walkSab',  { tor: 10, walk: 1, h1x: 46, h1y: 26, h2x: 18, h2y: 22, two: 1, sab: 52 });
defPose('runP',     { tor: 24, hd: 6, run: 1, h1x: -14, h1y: 8, sab: 200 });
defPose('runFwd',   { tor: 26, hd: 6, run: 1, h1x: 46, h1y: 16, sab: 25, two: 1 });

defPose('draw',     { tor: 6, hd: 4, h1x: 38, h1y: 30, sab: 90, two: 0, h2x: -6, h2y: 28, f1x: 14, f1y: -86, f2x: -14, f2y: -86 });
defPose('stance',   { tor: 12, hd: -4, h1x: 50, h1y: 32, two: 1, sab: 46, f1x: 40, f1y: -80, f2x: -36, f2y: -82 });
defPose('stanceB',  { tor: 8, hd: -2, h1x: 44, h1y: 30, two: 1, sab: 38, f1x: 34, f1y: -82, f2x: -32, f2y: -84 });
defPose('stanceLow',{ tor: 22, hd: -8, h1x: 56, h1y: 4, two: 1, sab: 14, f1x: 48, f1y: -66, f2x: -42, f2y: -70 });
defPose('onehand',  { tor: 6, hd: -3, h1x: 54, h1y: 22, two: 0, sab: 52, h2x: -26, h2y: 38, f1x: 34, f1y: -82, f2x: -32, f2y: -84 });
defPose('backhand', { tor: 4, h1x: -26, h1y: 30, sab: 158, two: 0, h2x: 40, h2y: 34, f1x: 30, f1y: -82, f2x: -30, f2y: -84 });

defPose('windHi',   { tor: -6, hd: -4, h1x: 8, h1y: 90, two: 1, sab: 150, f1x: 28, f1y: -84, f2x: -30, f2y: -84 });
defPose('strikeHi', { tor: 26, hd: 6, h1x: 62, h1y: 18, two: 1, sab: -42, f1x: 54, f1y: -72, f2x: -46, f2y: -82 });
defPose('windLow',  { tor: 8, h1x: -22, h1y: 8, two: 1, sab: 215, f1x: 32, f1y: -78, f2x: -34, f2y: -80 });
defPose('strikeLow',{ tor: 20, h1x: 62, h1y: 4, two: 1, sab: 352, f1x: 52, f1y: -66, f2x: -44, f2y: -76 });
defPose('windUp',   { tor: 22, h1x: 40, h1y: -8, two: 1, sab: -50, f1x: 44, f1y: -70, f2x: -38, f2y: -78 });
defPose('strikeUp', { tor: -4, hd: -6, h1x: 40, h1y: 70, two: 1, sab: 130, f1x: 36, f1y: -82, f2x: -34, f2y: -84 });
defPose('thrust',   { tor: 30, hd: 8, h1x: 68, h1y: 30, two: 1, sab: 4, f1x: 64, f1y: -60, f2x: -52, f2y: -84 });
defPose('coil',     { tor: -4, h1x: 4, h1y: 34, two: 1, sab: 8, f1x: 22, f1y: -82, f2x: -40, f2y: -80 });

defPose('blockHi',  { tor: 6, h1x: 46, h1y: 60, two: 1, sab: 96, f1x: 34, f1y: -80, f2x: -32, f2y: -82 });
defPose('blockMid', { tor: 10, h1x: 50, h1y: 34, two: 1, sab: 60, f1x: 38, f1y: -80, f2x: -34, f2y: -82 });
defPose('blockLow', { tor: 20, h1x: 50, h1y: 2, two: 1, sab: -62, f1x: 44, f1y: -66, f2x: -38, f2y: -72 });

defPose('kickF',    { tor: -16, hd: 4, h1x: -30, h1y: 34, sab: 140, two: 0, h2x: 26, h2y: 48, f1x: 96, f1y: -24, f2x: -8, f2y: -86 });
defPose('kickLow',  { tor: 8, h1x: -10, h1y: 20, sab: 120, h2x: 34, h2y: 30, f1x: 92, f1y: -64, f2x: -14, f2y: -86 });
defPose('pushP',    { tor: 14, hd: 2, h1x: -14, h1y: 2, sab: -100, two: 0, h2x: 72, h2y: 46, f1x: 44, f1y: -78, f2x: -42, f2y: -82 });
defPose('pushWind', { tor: -4, h1x: -18, h1y: 6, sab: -100, two: 0, h2x: 18, h2y: 40, f1x: 26, f1y: -82, f2x: -30, f2y: -84 });
defPose('pullP',    { tor: -10, hd: -4, h1x: -14, h1y: 6, sab: -100, two: 0, h2x: 44, h2y: 56, f1x: 30, f1y: -82, f2x: -34, f2y: -84 });
defPose('chokeP',   { tor: 6, h1x: -10, h1y: 8, sab: -100, two: 0, h2x: 62, h2y: 62, f1x: 28, f1y: -84, f2x: -26, f2y: -84 });

defPose('leap',     { tor: 10, h1x: 48, h1y: 50, two: 1, sab: 70, f1x: 28, f1y: -46, f2x: -14, f2y: -34 });
defPose('airStrike',{ tor: 22, h1x: 64, h1y: 22, two: 1, sab: -34, f1x: 34, f1y: -62, f2x: -34, f2y: -52 });
defPose('airWind',  { tor: 4, h1x: 10, h1y: 84, two: 1, sab: 150, f1x: 24, f1y: -50, f2x: -26, f2y: -44 });
defPose('tuck',     { tor: 34, hd: 10, h1x: 30, h1y: 8, two: 1, sab: 120, f1x: 22, f1y: -34, f2x: 4, f2y: -30 });
defPose('spread',   { tor: 0, hd: 0, h1x: 44, h1y: 40, sab: 40, two: 0, h2x: -38, h2y: 36, f1x: 34, f1y: -70, f2x: -34, f2y: -70 });
defPose('spin',     { tor: 10, h1x: 66, h1y: 34, sab: 0, two: 0, h2x: -50, h2y: 32, f1x: 28, f1y: -80, f2x: -28, f2y: -80 });

defPose('hurt',     { tor: -24, hd: -12, h1x: -34, h1y: 38, sab: 160, two: 0, h2x: -22, h2y: 54, f1x: 16, f1y: -80, f2x: -26, f2y: -80 });
defPose('hurtB',    { tor: 28, hd: 14, h1x: 10, h1y: -10, sab: 220, two: 0, h2x: 20, h2y: 0, f1x: 30, f1y: -60, f2x: -20, f2y: -70 });
defPose('fall',     { tor: -12, hd: -16, h1x: -44, h1y: 58, sab: 200, two: 0, h2x: -52, h2y: 36, f1x: 12, f1y: -84, f2x: -22, f2y: -82 });
defPose('crouch',   { tor: 30, hd: -10, h1x: 34, h1y: -4, sab: 20, two: 1, f1x: 34, f1y: -52, f2x: -30, f2y: -52 });
defPose('kneel',    { tor: 8, hd: 14, h1x: 14, h1y: -22, sab: -80, two: 0, h2x: 18, h2y: -18, f1x: 36, f1y: -46, f2x: -48, f2y: -50 });
defPose('kneelFist',{ tor: 22, hd: 24, h1x: 40, h1y: 4, sab: -90, two: 0, h2x: 52, h2y: -14, f1x: 40, f1y: -46, f2x: -48, f2y: -50 });
defPose('slump',    { tor: 20, hd: 28, h1x: 8, h1y: -30, sab: -90, two: 0, h2x: 4, h2y: -34, f1x: 30, f1y: -50, f2x: -46, f2y: -50 });
defPose('triumph',  { tor: -4, hd: -10, h1x: 38, h1y: 98, sab: 94, two: 0, h2x: -20, h2y: -14, f1x: 24, f1y: -86, f2x: -22, f2y: -86 });
defPose('lowered',  { tor: 10, hd: 12, h1x: 22, h1y: -22, sab: -88, two: 0, h2x: -10, h2y: -26, f1x: 12, f1y: -86, f2x: -10, f2y: -86 });
})(typeof window !== 'undefined' ? window : globalThis);
