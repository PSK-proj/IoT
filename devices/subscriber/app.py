import os, time, json, signal, sys, statistics
from datetime import datetime, timezone
import threading

import paho.mqtt.client as mqtt

DEVICE_NAME = os.environ.get("DEVICE_NAME", "subscriber-1")
MQTT_HOST = os.environ.get("MQTT_HOST", "broker")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_TLS  = os.environ.get("MQTT_TLS", "0") == "1"
MQTT_USER = os.environ.get("MQTT_USERNAME") or None
MQTT_PASS = os.environ.get("MQTT_PASSWORD") or None
TOPIC_SUB = os.environ.get("MQTT_TOPIC_SUB", "lab/telemetry/#")
TOPIC_METRICS = os.environ.get("MQTT_TOPIC_METRICS", "lab/metrics")
QOS       = int(os.environ.get("MQTT_QOS", "0"))
PERIOD    = float(os.environ.get("HEARTBEAT_SEC", "1.0"))

_running = True
lat_samples_ms = []

def _stop(sig, frame):
    global _running
    _running = False

signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

def _on_connect(client, userdata, flags, rc, properties=None):
    status = "OK" if rc == 0 else f"ERR({rc})"
    print(f"[{DEVICE_NAME}] connected -> {status}", flush=True)
    if rc == 0:
        client.subscribe(TOPIC_SUB, qos=QOS)
        print(f"[{DEVICE_NAME}] subscribed {TOPIC_SUB} qos={QOS}", flush=True)

def _on_message(client, userdata, msg):
    global lat_samples_ms
    try:
        data = json.loads(msg.payload.decode("utf-8"))
        t_send = data.get("ts_monotonic_ns")
        if isinstance(t_send, int):
            lat_ms = (time.monotonic_ns() - t_send) / 1_000_000.0
            lat_samples_ms.append(lat_ms)
            if len(lat_samples_ms) > 1000:
                lat_samples_ms = lat_samples_ms[-1000:]
            print(f"[{DEVICE_NAME}] <- {msg.topic} {data.get('device')} seq={data.get('seq')} lat={lat_ms:.2f}ms", flush=True)
        else:
            print(f"[{DEVICE_NAME}] <- {msg.topic} (no ts)", flush=True)
    except Exception as e:
        print(f"[{DEVICE_NAME}] decode error: {e}", flush=True)

def _on_disconnect(client, userdata, rc, properties=None):
    print(f"[{DEVICE_NAME}] disconnected rc={rc}", flush=True)

def _metrics_loop(client: mqtt.Client):
    while _running:
        time.sleep(max(PERIOD, 1.0))
        if lat_samples_ms:
            p50 = statistics.median(lat_samples_ms)
            p95 = statistics.quantiles(lat_samples_ms, n=20)[-1] if len(lat_samples_ms) >= 20 else p50
            metrics = {
                "device": DEVICE_NAME,
                "ts_utc": datetime.now(timezone.utc).isoformat(),
                "samples": len(lat_samples_ms),
                "p50_ms": round(p50, 2),
                "p95_ms": round(p95, 2),
            }
            client.publish(TOPIC_METRICS, json.dumps(metrics, separators=(",", ":")), qos=0, retain=False)

def _build_client() -> mqtt.Client:
    # paho-mqtt 2.x – zachowujemy stare sygnatury callbacków (API v1)
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION1,
        client_id=f"{DEVICE_NAME}",
        clean_session=True,
        protocol=mqtt.MQTTv311,
    )
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)
    if MQTT_TLS:
        client.tls_set()  # pełna konfiguracja TLS/mTLS w kroku 3/4
    client.on_connect = _on_connect
    client.on_message = _on_message
    client.on_disconnect = _on_disconnect
    client.reconnect_delay_set(min_delay=1, max_delay=10)
    return client

def main():
    print(f"[{DEVICE_NAME}] starting subscriber -> {MQTT_HOST}:{MQTT_PORT} TLS={MQTT_TLS} sub={TOPIC_SUB}", flush=True)
    client = _build_client()
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)

    t1 = threading.Thread(target=client.loop_forever, daemon=True)
    t1.start()
    t2 = threading.Thread(target=_metrics_loop, args=(client,), daemon=True)
    t2.start()

    while _running:
        time.sleep(0.5)

    try:
        client.disconnect()
    except Exception:
        pass
    print(f"[{DEVICE_NAME}] stopped", flush=True)

if __name__ == "__main__":
    main()
