// Level layouts. '.' is floor; every other character is a wall material:
//   T  grey tech panel      B  brown stone
//   #  steel pillar         S  slime-streaked pillar

export const WALL_STYLE = {
  T: { name: 'tech', lum: 0.72, rgb: [118, 124, 132] },
  B: { name: 'stone', lum: 0.48, rgb: [120, 86, 58] },
  '#': { name: 'steel', lum: 0.6, rgb: [96, 100, 110] },
  S: { name: 'slime', lum: 0.52, rgb: [84, 104, 70] },
};

const RAW = {
  // Open room with four pillars. Used for the valence-learning task.
  arena: {
    label: 'Arena',
    start: { x: 8.5, y: 13.5, angle: -Math.PI / 2 },
    rows: [
      'TTTTTTTTTTTTTTTT',
      'T..............T',
      'T..............T',
      'T...#......#...T',
      'T..............T',
      'T..............T',
      'T..............T',
      'T......SS......T',
      'T......SS......T',
      'T..............T',
      'T..............T',
      'T..............T',
      'T...#......#...T',
      'T..............T',
      'T..............T',
      'TTTTTTTTTTTTTTTT',
    ],
  },
  // A hangar loosely in the spirit of E1M1: side rooms, pillars, a slime court.
  hangar: {
    label: 'Hangar',
    start: { x: 11.5, y: 17.5, angle: -Math.PI / 2 },
    rows: [
      'TTTTTTTTTTTTTTTTTTTTTTTT',
      'T......B.........B.....T',
      'T......B.........B.....T',
      'T..BB.............BB...T',
      'T......B.........B.....T',
      'T......BBB.....BBB.....T',
      'TBB.BBBB...........BB.BT',
      'T..........#..#........T',
      'T..........#..#........T',
      'T..##..............##..T',
      'T..#................#..T',
      'T.......SS....SS.......T',
      'T.......SS....SS.......T',
      'T..#................#..T',
      'T..##..............##..T',
      'T......................T',
      'TBBBB.BBBBB..BBBBB.BBBBT',
      'T.........B..B.........T',
      'T.........B..B.........T',
      'TTTTTTTTTTTTTTTTTTTTTTTT',
    ],
  },
};

function compile(key, raw) {
  const height = raw.rows.length;
  const width = raw.rows[0].length;
  const cells = new Uint8Array(width * height);
  const open = [];
  raw.rows.forEach((row, y) => {
    if (row.length !== width) throw new Error(`map ${key}: row ${y} has ${row.length} cells, expected ${width}`);
    for (let x = 0; x < width; x++) {
      const ch = row[x];
      if (ch === '.') { open.push([x, y]); continue; }
      if (!WALL_STYLE[ch]) throw new Error(`map ${key}: unknown wall '${ch}'`);
      cells[y * width + x] = ch.charCodeAt(0);
    }
  });
  return { key, label: raw.label, width, height, cells, open, start: raw.start, rows: raw.rows };
}

export const MAPS = Object.fromEntries(Object.entries(RAW).map(([k, v]) => [k, compile(k, v)]));
