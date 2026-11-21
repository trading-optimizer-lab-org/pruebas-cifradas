import json, sys
# Reparte las líneas del plan: t, las que no necesitan las APK (la 0 las compila); e1 y e2, las de emulador, que esperan a t.
# Los emuladores van en dos mitades porque GitHub no deja más de 256 máquinas en un mismo grupo.
t, e = [], []
for i, l in enumerate(x for x in open(sys.argv[1]) if x.strip()):
    (e if l.split()[0] in ("emu", "mono", "rec") else t).append(i)
m = (len(e) + 1) // 2
print("t=" + json.dumps(t))
print("e1=" + json.dumps(e[:m]))
print("e2=" + json.dumps(e[m:]))
