#!/usr/bin/env python3
# Expose host Ollama (127.0.0.1:11434) on 0.0.0.0:11435 so containers on a
# bridge network can reach it via host-gateway. No sudo, no systemd change.
import socket, threading, sys
LISTEN=("0.0.0.0",11435); TARGET=("127.0.0.1",11434)
def pipe(a,b):
    try:
        while True:
            d=a.recv(65536)
            if not d: break
            b.sendall(d)
    except OSError: pass
    finally:
        for s in (a,b):
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass
def handle(c):
    try:
        u=socket.create_connection(TARGET)
    except OSError:
        c.close(); return
    threading.Thread(target=pipe,args=(c,u),daemon=True).start()
    threading.Thread(target=pipe,args=(u,c),daemon=True).start()
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(LISTEN); s.listen(64)
print(f"forwarding {LISTEN} -> {TARGET}",flush=True)
while True:
    c,_=s.accept(); handle(c)
