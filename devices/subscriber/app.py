import os, time, signal, sys

name = os.environ.get("DEVICE_NAME", "subscriber")
period = float(os.environ.get("HEARTBEAT_SEC", "5"))

running = True
def stop(sig, frame):
    global running
    running = False
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)

print(f"[{name}] started (heartbeat every {period}s)", flush=True)
i = 0
while running:
    i += 1
    print(f"[{name}] alive #{i}", flush=True)
    time.sleep(period)

print(f"[{name}] stopping", flush=True)
sys.exit(0)
