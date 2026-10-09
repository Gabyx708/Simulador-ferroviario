import json
from collections import defaultdict, deque

with open('tramo_completo_constitucion_bosques/red_godot_constitucion_bosques.json', 'r', encoding='utf-8') as f:
    clean = json.load(f)

adj = defaultdict(list)
for jid, j in clean['junctions'].items():
    segs = [entry['segment_id'] for entry in j.get('segments', [])]
    for s1 in segs:
        for s2 in segs:
            if s1 != s2:
                adj[s1].append((s2, jid))

print(f"Total segments: {len(clean['segments'])}")
print(f"Segments in adjacency: {len(adj)}")

start_segs = [s['id'] for s in clean['segments'] if s.get('tramo') == '01_Plaza_Constitucion']
end_segs = set(s['id'] for s in clean['segments'] if s.get('tramo') == '16_Zeballos_Bosques')

print(f"Start segs (Constitucion): {len(start_segs)}")
print(f"End segs (Bosques): {len(end_segs)}")

visited = set()
queue = deque(start_segs)
for s in start_segs:
    visited.add(s)

while queue:
    curr = queue.popleft()
    for neighbor, jid in adj[curr]:
        if neighbor not in visited:
            visited.add(neighbor)
            queue.append(neighbor)

reached_bosques = [s for s in end_segs if s in visited]
print(f"Can reach Bosques from Constitucion? {len(reached_bosques)} / {len(end_segs)} Bosques tracks reached!")
if not reached_bosques:
    print("DISCONNECTED!")
    seg_map = {s['id']: s for s in clean['segments']}
    max_z = max(max(p['z'] for p in seg_map[s]['points']) for s in visited)
    max_x = max(max(p['x'] for p in seg_map[s]['points']) for s in visited)
    print(f"Furthest point reached: max_z={max_z:.1f}, max_x={max_x:.1f}")

    # Check which segments near Temperley were NOT visited
    temperley_segs = [s['id'] for s in clean['segments'] if s.get('sector') in ['Sector_03_Lanus_Temperley', 'Sector_04_Temperley_Claypole']]
    not_visited_temp = [s for s in temperley_segs if s not in visited]
    print(f"Temperley/Marmol segments not reached: {len(not_visited_temp)} / {len(temperley_segs)}")
    print("Sample not reached:", not_visited_temp[:15])
else:
    print("SUCCESS: Network is fully connected from Constitucion to Bosques!")
