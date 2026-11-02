"""Cook mesh-derived convex pieces offline; the app only loads the small JSON.

Requires numpy, trimesh, scipy, coacd (tested with coacd 1.0.9).
First export an OBJ with ExportRockyCollisionMesh.swift, using the app's target size.
Usage: python Tools/GenerateRockyColliders.py input.obj source.usdz output.json tolerance_metres
"""
import hashlib
import json
import sys
from pathlib import Path
import coacd
import numpy as np
import trimesh

source, asset, output = map(Path, sys.argv[1:4])
tolerance = float(sys.argv[4])
mesh = trimesh.load(source, force="mesh")
components = sorted(mesh.split(only_watertight=False), key=lambda m: -len(m.faces))
hulls = []
coacd.set_log_level("warn")
for index, component in enumerate(components):
    if len(component.faces) < 4:
        # The model contains one isolated degenerate triangle, not a solid part.
        continue
    component.fix_normals()
    parts = coacd.run_coacd(
        coacd.Mesh(component.vertices, component.faces),
        threshold=tolerance, real_metric=True, max_convex_hull=64,
        preprocess_mode="auto", preprocess_resolution=70,
        resolution=2000, mcts_iterations=100, mcts_max_depth=3,
        decimate=True, max_ch_vertex=64, seed=42,
    )
    for vertices, faces in parts:
        # Persist triangle topology as well for inspection and regression checks.
        hulls.append({"vertices": np.round(vertices, 8).tolist(), "triangles": faces.tolist()})
    print(f"{asset.name} part {index+1}/{len(components)}: {len(parts)} hulls, total {len(hulls)}", flush=True)
result = {
    "version": 1,
    "sourceAsset": asset.name,
    "sourceSHA256": hashlib.sha256(asset.read_bytes()).hexdigest(),
    "generator": "CoACD 1.0.9; seed=42; per connected component; max 64 vertices per hull",
    "toleranceMetres": tolerance,
    "boundsMinimum": mesh.bounds[0].tolist(),
    "boundsMaximum": mesh.bounds[1].tolist(),
    "hulls": hulls,
}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, separators=(",", ":")) + "\n")
print(f"Wrote {output}: {len(hulls)} convex shapes", flush=True)
