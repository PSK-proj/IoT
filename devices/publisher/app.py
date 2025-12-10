import os, time, json, signal, threading
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

DEVICE_NAME = os.environ.get("DEVICE_NAME", "publisher-1")

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

TOPIC_PUB = (os.environ.get("MQTT_TOPIC_PUB") or f"lab/telemetry/{DEVICE_NAME}")
QOS = int(os.environ.get("MQTT_QOS", "0"))
PERIOD = float(os.environ.get("HEARTBEAT_SEC", "1.0"))

_running = True
_client_lock = threading.RLock()
_client = None
_mode = MQTT_MODE_DEFAULT if MQTT_MODE_DEFAULT in ("PLAIN", "TLS", "MTLS") else "PLAIN"

def _stop(sig, frame):
    global _running
    _running = False

signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

def _on_connect(client, userdata, flags, rc, properties=None):
    status = "OK" if rc == 0 else f"ERR({rc})"
    print(f"[{DEVICE_NAME}] connected ({_mode}) -> {status}", flush=True)
    if rc == 0:
        client.subscribe(MQTT_CONTROL_TOPIC, qos=1)

def _on_message(client, userdata, msg):
    global _mode
    try:
        s = msg.payload.decode("utf-8", errors="replace").strip().upper()
        target = "MTLS" if s == "MODE=MTLS" else "TLS" if s == "MODE=TLS" else "PLAIN" if s == "MODE=PLAIN" else None
        if target and target != _mode:
            print(f"[{DEVICE_NAME}] control: switch {_mode} -> {target}", flush=True)
            _switch_mode(target)
    except Exception as e:
        print(f"[{DEVICE_NAME}] control decode error: {e}", flush=True)

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

def _now_ns():
    return time.monotonic_ns()

def main():
    print(f"[{DEVICE_NAME}] starting publisher | default_mode={_mode} pub={TOPIC_PUB}", flush=True)
    _switch_mode(_mode)
    i = 0
    try:
        while _running:
            i += 1
            payload = {"device": DEVICE_NAME, "seq": i, "ts_monotonic_ns": _now_ns(), "ts_utc": datetime.now(timezone.utc).isoformat(), "msg": "heartbeat"}
            b = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            with _client_lock:
                c = _client
            if c is not None:
                res = c.publish(TOPIC_PUB, b, qos=QOS, retain=False)
                if res.rc != mqtt.MQTT_ERR_SUCCESS:
                    print(f"[{DEVICE_NAME}] publish rc={res.rc}", flush=True)
            time.sleep(PERIOD)
    finally:
        with _client_lock:
            if _client is not None:
                _teardown_client(_client)
        print(f"[{DEVICE_NAME}] stopped", flush=True)

if __name__ == "__main__":
    main()
