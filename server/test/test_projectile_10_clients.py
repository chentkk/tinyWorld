#!/usr/bin/env python3
# 10 clients 场景: 4 cellapp 4 cells, 玩家集中在空间中心附近。
# 玩家1释放直线投掷物(右), 统计每个目标收到的 onCombatDamage 次数与 entityId。
import json, socket, struct, time, urllib.request

HOST="127.0.0.1"; LOGIN=8080; GAME=8000
N=10

def login(name):
    r=urllib.request.urlopen(f"http://{HOST}:{LOGIN}/login?name={name}&password=123456")
    return json.loads(r.read().decode())

def connect():
    s=socket.socket(); s.settimeout(2); s.connect((HOST,GAME)); return s

def send(s,t,n,d=None):
    body=json.dumps({"t":t,"n":n,"d":d or {}}).encode()
    s.sendall(struct.pack("<H",len(body))+body)

def recv(s):
    h=b""
    while len(h)<2:
        c=s.recv(2-len(h))
        if not c: return None
        h+=c
    n=struct.unpack("<H",h)[0]
    b=b""
    while len(b)<n:
        c=s.recv(n-len(b))
        if not c: return None
        b+=c
    return json.loads(b.decode())

def wait(s,t,n,timeout=5):
    end=time.time()+timeout
    while time.time()<end:
        try: m=recv(s)
        except socket.timeout: continue
        if not m: return None
        if m.get("t")==t and m.get("n")==n: return m
    return None

login_cache=[]
for i in range(1,N+1):
    tok=login(f"test{i}")
    assert tok.get("code")==0, tok
    login_cache.append(tok["token"])

clients=[]
for i,token in enumerate(login_cache,1):
    s=connect()
    send(s,"AUTH","auth",{"token":token})
    wait(s,"AUTH","auth_ok")
    send(s,"ACCOUNT","characterList",{})
    wait(s,"ACCOUNT","characterList")
    send(s,"ACCOUNT","selectCharacter",{"playerId":i})
    # 等待 self object add
    end=time.time()+3
    while time.time()<end:
        try: m=recv(s)
        except socket.timeout: continue
        if m and m.get("t")=="object" and m.get("n")=="add" and (m.get("d") or {}).get("isSelf"):
            break
    clients.append(s)
print(f"进入世界 {len(clients)} 个客户端")

caster=clients[0]
send(caster,"RPC","onCastAbility",{"index":6,"targetId":0})

end=time.time()+10
stats={}
while time.time()<end:
    for idx,s in enumerate(clients,1):
        s.settimeout(0.02)
        try: m=recv(s)
        except socket.timeout: continue
        if not m: continue
        if m.get("t")=="RPC" and m.get("n")=="onCombatDamage":
            d=m.get("d") or {}
            key=(d.get("entityId"), d.get("amount"), d.get("skill"))
            stats[key]=stats.get(key,0)+1
            print("DAMAGE", idx, d)
        elif m.get("t")=="object" and m.get("n") in ("add","remove") and (m.get("d") or {}).get("kind")=="Projectile":
            print("PROJ", idx, m)

print("=== damage stats ===")
for k,v in sorted(stats.items()):
    print(k,v)
for s in clients: s.close()
