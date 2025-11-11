import os, time, json, signal, statistics, threading
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

DEVICE_NAME = os.environ.get("DEVICE_NAME", "subscriber-1")

MQTT_MODE_DEFAULT = os.environ.get("MQTT_MODE_DEFAULT", "PLAIN").upper()
MQTT_CONTROL_TOPIC = os.environ.get("MQTT_CONTROL_TOPIC", "lab/control")

MQTT_PLAIN_HOST = os.environ.get("MQTT_PLAIN_HOST", "broker")
MQTT_PLAIN_PORT = int(os.environ.get("MQTT_PLAIN_PORT", "1883"))

MQTT_TLS_HOST = os.environ.get("MQTT_TLS_HOST", "broker")
MQTT_TLS_PORT = int(os.environ.get("MQTT_TLS_PORT", "8883"))
MQTT_TLS_CA = os.environ.get("MQTT_TLS_CA", "/certs/ca.crt")

MQTT_MTLS_HOST = os.environ.get("MQTT_MTLS_HOST", "broker")
MQTT_MTLS_PORT = int(os.environ.get("MQTT_MTLS_PORT", "8884"))
MQTT_CLIENT_CERT = os.environ.get("MQTT_CLIENT_CERT", f"/certs/clients/{DEVICE_NAME}.crt")
MQTT_CLIENT_KEY = os.environ.get("MQTT_CLIENT_KEY", f"/certs/clients/{DEVICE_NAME}.key")

MQTT_USER = os.environ.get("MQTT_USERNAME") or None
MQTT_PASS = os.environ.get("MQTT_PASSWORD") or None

TOPIC_SUB = os.environ.get("MQTT_TOPIC_SUB", "lab/telemetry/#")
TOPIC_METRICS = os.environ.get("MQTT_TOPIC_METRICS", "lab/metrics")
QOS = int(os.environ.get("MQTT_QOS", "0"))
PERIOD = float(os.environ.get("HEARTBEAT_SEC", "1.0"))

_running = True
_client_lock = threading.RLock()
_client = None
_mode = MQTT_MODE_DEFAULT if MQTT_MODE_DEFAULT in ("PLAIN", "TLS", "MTLS") else "PLAIN"
lat_samples_ms = []

def _stop(sig, frame):
    global _running
    _running = False

signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

def _on_connect(client, userdata, flags, rc, properties=None):
    status = "OK" if rc == 0 else f"ERR({rc})"
    print(f"[{DEVICE_NAME}] connected ({_mode}) -> {status}", flush=True)
    if rc == 0:
        client.subscribe(TOPIC_SUB, qos=QOS)
        client.subscribe(MQTT_CONTROL_TOPIC, qos=1)

def _on_message(client, userdata, msg):
    global lat_samples_ms, _mode
    if msg.topic == MQTT_CONTROL_TOPIC:
        try:
            s = msg.payload.decode("utf-8", errors="replace").strip().upper()
            target = "MTLS" if s == "MODE=MTLS" else "TLS" if s == "MODE=TLS" else "PLAIN" if s == "MODE=PLAIN" else None
            if target and target != _mode:
                print(f"[{DEVICE_NAME}] control: switch {_mode} -> {target}", flush=True)
                _switch_mode(target)
            return
        except Exception as e:
            print(f"[{DEVICE_NAME}] control decode error: {e}", flush=True)
            return
    try:
        data = json.loads(msg.payload.decode("utf-8"))
        t_send = data.get("ts_monotonic_ns")
        if isinstance(t_send, int):
            lat_ms = (time.monotonic_ns() - t_send) / 1_000_000.0
            lat_samples_ms.append(lat_ms)
            if len(lat_samples_ms) > 1000:
                lat_samples_ms = lat_samples_ms[-1000:]
            print(f"[{DEVICE_NAME}] <- {msg.topic} {data.get('device')} seq={data.get('seq')} lat={lat_ms:.2f}ms", flush=True)
    except Exception as e:
        print(f"[{DEVICE_NAME}] decode error: {e}", flush=True)

def _on_disconnect(client, userdata, rc, properties=None):
    print(f"[{DEVICE_NAME}] disconnected rc={rc}", flush=True)

def _build_client(mode: str) -> mqtt.Client:
    c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=f"{DEVICE_NAME}", clean_session=True, protocol=mqtt.MQTTv311)
    if MQTT_USER:
        c.username_pw_set(MQTT_USER, MQTT_PASS)
    if mode == "TLS":
        ca = MQTT_TLS_CA if os.path.exists(MQTT_TLS_CA) else None
        c.tls_set(ca_certs=ca)
        c.tls_insecure_set(False)
    if mode == "MTLS":
        ca = MQTT_TLS_CA if os.path.exists(MQTT_TLS_CA) else None
        certf = MQTT_CLIENT_CERT if os.path.exists(MQTT_CLIENT_CERT) else None
        keyf = MQTT_CLIENT_KEY if os.path.exists(MQTT_CLIENT_KEY) else None
        c.tls_set(ca_certs=ca, certfile=certf, keyfile=keyf)
        c.tls_insecure_set(False)
    c.on_connect = _on_connect
    c.on_message = _on_message
    c.on_disconnect = _on_disconnect
    c.reconnect_delay_set(min_delay=1, max_delay=10)
    return c

def _connect_current(client: mqtt.Client, mode: str):
    if mode == "MTLS":
        host, port = MQTT_MTLS_HOST, MQTT_MTLS_PORT
    elif mode == "TLS":
        host, port = MQTT_TLS_HOST, MQTT_TLS_PORT
    else:
        host, port = MQTT_PLAIN_HOST, MQTT_PLAIN_PORT
    client.connect(host, port, keepalive=30)
    client.loop_start()
    print(f"[{DEVICE_NAME}] dial {mode} -> {host}:{port}", flush=True)

def _teardown_client(c: mqtt.Client):
    try:
        c.disconnect()
    except Exception:
        pass
    time.sleep(0.1)
    try:
        c.loop_stop()
    except Exception:
        pass

def _switch_mode(target: str):
    global _client, _mode
    with _client_lock:
        old = _client
        new = _build_client(target)
        _connect_current(new, target)
        _client = new
        _mode = target
    if old is not None:
        _teardown_client(old)

def _metrics_loop():
    while _running:
        time.sleep(max(PERIOD, 1.0))
        if lat_samples_ms:
            p50 = statistics.median(lat_samples_ms)
            p95 = statistics.quantiles(lat_samples_ms, n=20)[-1] if len(lat_samples_ms) >= 20 else p50
            metrics = {"device": DEVICE_NAME, "ts_utc": datetime.now(timezone.utc).isoformat(), "samples": len(lat_samples_ms), "p50_ms": round(p50, 2), "p95_ms": round(p95, 2)}
            payload = json.dumps(metrics, separators=(",", ":"))
            with _client_lock:
                c = _client
            if c is not None:
                c.publish(TOPIC_METRICS, payload, qos=0, retain=False)

def main():
    print(f"[{DEVICE_NAME}] starting subscriber | default_mode={_mode} sub={TOPIC_SUB}", flush=True)
    _switch_mode(_mode)
    t = threading.Thread(target=_metrics_loop, daemon=True)
    t.start()
    try:
        while _running:
            time.sleep(0.5)
    finally:
        with _client_lock:
            if _client is not None:
                _teardown_client(_client)
        print(f"[{DEVICE_NAME}] stopped", flush=True)

if __name__ == "__main__":
    main()
