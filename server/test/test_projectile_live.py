#!/usr/bin/env python3
import json, socket, struct, time, urllib.request

HOST = "127.0.0.1"; LOGIN = 8080; GAME = 8000

def login(name):
    r = urllib.request.urlopen(f"http://{HOST}:{LOGIN}/login?name={name}&password=123456")
    return json.loads(r.read().decode())

def connect():
    s = socket.socket(); s.settimeout(2); s.connect((HOST, GAME)); return s

def send(s, t, n, d=None):
    body = json.dumps({"t": t, "n": n, "d": d or {}}).encode()
    s.sendall(struct.pack("<H", len(body)) + body)

def recv(s):
    h = b""
    while len(h) < 2:
        c = s.recv(2-len(h))
        if not c: return None
        h += c
    n = struct.unpack("<H", h)[0]
    b = b""
    while len(b) < n:
        c = s.recv(n-len(b))
        if not c: return None
        b += c
    return json.loads(b.decode())

def wait(s, t, n, timeout=4):
    end = time.time() + timeout
    while time.time() < end:
        try: m = recv(s)
        except socket.timeout: continue
        if not m: return None
        if m.get("t") == t and m.get("n") == n: return m
    return None

WANTED = {
    ("RPC","onSpellCast"), ("RPC","onCombatDamage"), ("RPC","onCombatHeal"),
    ("object","add"), ("object","remove"),
    ("view","modifiers_view"), ("view","abilities_view"),
    ("prop","props"),
}

def drain(s, seconds):
    out = []
    end = time.time() + seconds
    s.settimeout(0.05)
    while time.time() < end:
        try: m = recv(s)
        except socket.timeout: continue
        if not m: continue
        if (m.get("t"), m.get("n")) in WANTED:
            out.append(m)
    return out

toks = [login("test1"), login("test2")]
s1, s2 = connect(), connect()
send(s1, "AUTH", "auth", {"token": toks[0]["token"]}); send(s2, "AUTH", "auth", {"token": toks[1]["token"]})
wait(s1, "AUTH", "auth_ok"); wait(s2, "AUTH", "auth_ok")
send(s1, "ACCOUNT", "characterList", {}); send(s2, "ACCOUNT", "characterList", {})
wait(s1, "ACCOUNT", "characterList"); wait(s2, "ACCOUNT", "characterList")
send(s1, "ACCOUNT", "selectCharacter", {"playerId": 1}); time.sleep(1)
send(s2, "ACCOUNT", "selectCharacter", {"playerId": 2}); time.sleep(2)

print("== tracking projectile ==")
send(s1, "RPC", "onCastAbility", {"index": 5, "targetId": 2})
for m in drain(s1, 4) + drain(s2, 4):
    t, n = m.get("t"), m.get("n")
    if t == "object" or t == "prop" or (t == "RPC" and n in ("onSpellCast","onCombatDamage","onCombatHeal")):
        print(t, n, m.get("d"))

time.sleep(5)
print("== linear projectile ==")
send(s1, "RPC", "onCastAbility", {"index": 6, "targetId": 0})
for m in drain(s1, 6) + drain(s2, 6):
    t, n = m.get("t"), m.get("n")
    if t == "object" or t == "prop" or (t == "RPC" and n in ("onSpellCast","onCombatDamage","onCombatHeal")):
        print(t, n, m.get("d"))

s1.close(); s2.close()
