import os, time, json, signal, sys, socket
from datetime import datetime, timezone
import threading

import paho.mqtt.client as mqtt

DEVICE_NAME = os.environ.get("DEVICE_NAME", "publisher-1")
MQTT_HOST = os.environ.get("MQTT_HOST", "broker")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_TLS  = os.environ.get("MQTT_TLS", "0") == "1"
MQTT_USER = os.environ.get("MQTT_USERNAME") or None
MQTT_PASS = os.environ.get("MQTT_PASSWORD") or None
TOPIC_PUB = os.environ.get("MQTT_TOPIC_PUB", f"lab/telemetry/{DEVICE_NAME}")
QOS       = int(os.environ.get("MQTT_QOS", "0"))
PERIOD    = float(os.environ.get("HEARTBEAT_SEC", "1.0"))

_running = True

def _stop(sig, frame):
    global _running
    _running = False

signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

def _on_connect(client, userdata, flags, rc, properties=None):
    status = "OK" if rc == 0 else f"ERR({rc})"
    print(f"[{DEVICE_NAME}] connected -> {status}", flush=True)

def _on_disconnect(client, userdata, rc, properties=None):
    print(f"[{DEVICE_NAME}] disconnected rc={rc}", flush=True)

def _build_client() -> mqtt.Client:
    # Uwaga: paho-mqtt 2.x – zachowujemy stare sygnatury callbacków (API v1)
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION1,
        client_id=f"{DEVICE_NAME}",
        clean_session=True,
        protocol=mqtt.MQTTv311,
    )
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)
    if MQTT_TLS:
        # TLS/mTLS skonfigurujemy w kroku 3/4 (tu placeholder)
        client.tls_set()
    client.on_connect = _on_connect
    client.on_disconnect = _on_disconnect
    client.reconnect_delay_set(min_delay=1, max_delay=10)
    return client

def _now_ns():
    return time.monotonic_ns()

def main():
    print(f"[{DEVICE_NAME}] starting publisher -> {MQTT_HOST}:{MQTT_PORT} TLS={MQTT_TLS} topic={TOPIC_PUB} qos={QOS}", flush=True)
    client = _build_client()
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)

    t = threading.Thread(target=client.loop_forever, daemon=True)
    t.start()

    i = 0
    while _running:
        i += 1
        payload = {
            "device": DEVICE_NAME,
            "seq": i,
            "ts_monotonic_ns": _now_ns(),
            "ts_utc": datetime.now(timezone.utc).isoformat(),
            "msg": "heartbeat"
        }
        b = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        res = client.publish(TOPIC_PUB, b, qos=QOS, retain=False)
        if res.rc != mqtt.MQTT_ERR_SUCCESS:
            print(f"[{DEVICE_NAME}] publish failed rc={res.rc}", flush=True)
        else:
            print(f"[{DEVICE_NAME}] -> {TOPIC_PUB} #{i} ({len(b)}B)", flush=True)
        time.sleep(PERIOD)

    try:
        client.disconnect()
    except Exception:
        pass
    print(f"[{DEVICE_NAME}] stopped", flush=True)

if __name__ == "__main__":
    main()
