"""Anteprima di tk-pdf mobile: serve la build web e la fotografa con Chrome headless, formato telefono.

Uso:  python tools/anteprima.py [nome-scatto ...]
Prima serve:  flutter build web
"""
import base64, http.server, json, os, socketserver, subprocess, sys, threading, time, urllib.request

import websocket

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(RADICE, "build", "web")
OUT = os.path.join(RADICE, "anteprime")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
W, H, DPR = 390, 844, 2
PORTA_WEB, PORTA_CDP = 8766, 9346

os.makedirs(OUT, exist_ok=True)


class Silenzioso(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB, **k)

    def log_message(self, *a):
        pass


server = socketserver.TCPServer(("127.0.0.1", PORTA_WEB), Silenzioso)
threading.Thread(target=server.serve_forever, daemon=True).start()

profilo = os.path.join(OUT, "profilo-chrome")
chrome = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
                           f"--remote-debugging-port={PORTA_CDP}", "--remote-allow-origins=*",
                           f"--user-data-dir={profilo}", f"--window-size={W},{H}", "about:blank"])
pagina = None
for _ in range(40):
    try:
        schede = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{PORTA_CDP}/json").read())
        pagina = [t for t in schede if t["type"] == "page"][0]
        break
    except Exception:
        time.sleep(0.5)
if pagina is None:
    print("Chrome non risponde")
    sys.exit(1)

ws = websocket.create_connection(pagina["webSocketDebuggerUrl"], suppress_origin=True, timeout=60)
_id = 0
errori = []


def cmd(metodo, **parametri):
    global _id
    _id += 1
    ws.send(json.dumps({"id": _id, "method": metodo, "params": parametri}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == _id:
            return m.get("result", {})
        if m.get("method") in ("Runtime.exceptionThrown", "Log.entryAdded"):
            errori.append(json.dumps(m.get("params"))[:300])


def scatto(nome, attesa=2.0):
    time.sleep(attesa)
    r = cmd("Page.captureScreenshot", format="png")
    percorso = os.path.join(OUT, nome + ".png")
    with open(percorso, "wb") as fh:
        fh.write(base64.b64decode(r["data"]))
    print("scatto:", percorso)


def tocca(x, y):
    cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[{"x": x, "y": y}])
    cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])


cmd("Runtime.enable"); cmd("Log.enable"); cmd("Page.enable")
cmd("Emulation.setDeviceMetricsOverride", width=W, height=H, deviceScaleFactor=DPR, mobile=True)
cmd("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
cmd("Emulation.setUserAgentOverride",
    userAgent="Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36")
cmd("Page.navigate", url=f"http://127.0.0.1:{PORTA_WEB}/")
time.sleep(7)

passi = sys.argv[1:] or ["home"]
for passo in passi:
    tipo, _, valore = passo.partition(":")
    if tipo == "tap":
        x, y = map(float, valore.split(","))
        tocca(x, y)
    elif tipo == "trascina":  # trascina:x1,y1,x2,y2 — il dito resta giù (per fotografare la lente)
        x1, y1, x2, y2 = map(float, valore.split(","))
        cmd("Input.dispatchTouchEvent", type="touchStart", touchPoints=[{"x": x1, "y": y1}])
        for k in range(1, 13):
            cmd("Input.dispatchTouchEvent", type="touchMove",
                touchPoints=[{"x": x1 + (x2 - x1) * k / 12, "y": y1 + (y2 - y1) * k / 12}])
            time.sleep(0.03)
    elif tipo == "rilascia":
        cmd("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
    elif tipo == "attesa":
        time.sleep(float(valore))
    else:
        scatto(passo)

if errori:
    print("ERRORI DALLA PAGINA:")
    for e in errori[-15:]:
        print("  ", e)
ws.close()
chrome.terminate()
server.shutdown()
