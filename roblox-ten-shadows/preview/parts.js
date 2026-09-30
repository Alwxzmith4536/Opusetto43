// Builds three.js meshes from assets/models.json, using the same part list,
// sizes, CFrame angles and materials that ModelFactory.luau uses in Roblox.
import * as THREE from "three";

const geoCache = new Map();

function wedgeGeometry() {
  // Roblox WedgePart: full bottom face, full back face (+Z), slope down to the front (-Z).
  const g = new THREE.BufferGeometry();
  const v = [
    [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], // bottom
    [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5], // top back edge
  ];
  const tris = [
    [0, 2, 1], [0, 3, 2], // bottom
    [3, 4, 5], [3, 5, 2], // back
    [0, 1, 5], [0, 5, 4], // slope
    [0, 4, 3], // left
    [1, 2, 5], // right
  ];
  const pos = [];
  for (const t of tris) for (const i of t) pos.push(...v[i]);
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

function geometryFor(shape) {
  if (geoCache.has(shape)) return geoCache.get(shape);
  let g;
  if (shape === "Ball") g = new THREE.SphereGeometry(0.5, 24, 16);
  else if (shape === "Cylinder") {
    g = new THREE.CylinderGeometry(0.5, 0.5, 1, 24);
    g.rotateZ(-Math.PI / 2); // Roblox cylinders run along X
  } else if (shape === "Wedge") g = wedgeGeometry();
  else g = new THREE.BoxGeometry(1, 1, 1);
  geoCache.set(shape, g);
  return g;
}

export function materialFor(p) {
  const c = new THREE.Color(`rgb(${p.color[0]},${p.color[1]},${p.color[2]})`);
  const opts = { color: c, transparent: p.transparency > 0, opacity: 1 - p.transparency };
  if (p.material === "Neon") {
    return new THREE.MeshBasicMaterial({ ...opts, color: c.clone().multiplyScalar(1.6) });
  }
  if (p.material === "Metal") return new THREE.MeshStandardMaterial({ ...opts, metalness: 0.75, roughness: 0.32 });
  return new THREE.MeshStandardMaterial({ ...opts, metalness: 0.02, roughness: 0.62 });
}

export function partMesh(p, scale = 1) {
  const mesh = new THREE.Mesh(geometryFor(p.shape), materialFor(p));
  let [sx, sy, sz] = p.size;
  if (p.shape === "Ball") sx = sy = sz = Math.min(sx, sy, sz);
  if (p.shape === "Cylinder") sy = sz = Math.min(sy, sz);
  mesh.scale.set(sx * scale, sy * scale, sz * scale);
  mesh.position.set(p.pos[0] * scale, p.pos[1] * scale, p.pos[2] * scale);
  const d = Math.PI / 180;
  mesh.rotation.set(p.rot[0] * d, p.rot[1] * d, p.rot[2] * d, "XYZ"); // == CFrame.Angles
  mesh.castShadow = p.material !== "Neon";
  mesh.receiveShadow = true;
  mesh.userData.part = p;
  return mesh;
}

// Returns a Group; joint groups (Wheel, RightArm, LeftArm) become child pivots so they can animate.
export function buildModel(data, scale = 1) {
  const root = new THREE.Group();
  const pivots = {};
  for (const [name, j] of Object.entries(data.joints || {})) {
    const pv = new THREE.Group();
    pv.position.set(j.pivot[0] * scale, j.pivot[1] * scale, j.pivot[2] * scale);
    root.add(pv);
    pivots[name] = pv;
  }
  for (const p of data.parts) {
    const mesh = partMesh(p, scale);
    const pv = pivots[p.group];
    if (pv) {
      mesh.position.sub(pv.position);
      pv.add(mesh);
    } else root.add(mesh);
  }
  root.userData.pivots = pivots;
  return root;
}
