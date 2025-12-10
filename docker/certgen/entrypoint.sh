#!/usr/bin/env sh
set -eu

CERTS_DIR="${CERTS_DIR:-/work/certs}"
mkdir -p "$CERTS_DIR" "$CERTS_DIR/clients"

CA_SUBJ="${CA_SUBJ:-/C=PL/O=IoTLab/CN=IoTLab-CA}"
SRV_CN="${SRV_CN:-broker}"
SRV_SAN="${SRV_SAN:-DNS:broker,DNS:localhost}"
DAYS_CA="${DAYS_CA:-3650}"
DAYS_SRV="${DAYS_SRV:-825}"

CLIENT_CN_LIST="${CLIENT_CN_LIST:-}"

CA_KEY="$CERTS_DIR/ca.key"
CA_CRT="$CERTS_DIR/ca.crt"
SRV_KEY="$CERTS_DIR/${SRV_CN}.key"
SRV_CRT="$CERTS_DIR/${SRV_CN}.crt"
SRV_CSR="$CERTS_DIR/${SRV_CN}.csr"
SRV_CNF="$CERTS_DIR/openssl.server.cnf"

echo "[certgen] CERTS_DIR=$CERTS_DIR"
echo "[certgen] SRV_CN=$SRV_CN  SRV_SAN=$SRV_SAN"
[ -n "$CLIENT_CN_LIST" ] && echo "[certgen] CLIENT_CN_LIST=$CLIENT_CN_LIST"

if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CRT" ]; then
  echo "[certgen] Generowanie CA…"
  openssl genrsa -out "$CA_KEY" 4096 >/dev/null 2>&1
  openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days "$DAYS_CA" -subj "$CA_SUBJ" -out "$CA_CRT" >/dev/null 2>&1
else
  echo "[certgen] CA już istnieje."
fi

cat > "$SRV_CNF" <<EOF
[ req ]
default_bits = 2048
distinguished_name = dn
req_extensions = req_ext
prompt = no

[ dn ]
C  = PL
O  = IoTLab
CN = ${SRV_CN}

[ req_ext ]
subjectAltName = ${SRV_SAN}
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
EOF

if [ ! -f "$SRV_KEY" ] || [ ! -f "$SRV_CRT" ]; then
  echo "[certgen] Generowanie cert serwera…"
  openssl genrsa -out "$SRV_KEY" 2048 >/dev/null 2>&1
  openssl req -new -key "$SRV_KEY" -out "$SRV_CSR" -config "$SRV_CNF" >/dev/null 2>&1
  openssl x509 -req -in "$SRV_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial -out "$SRV_CRT" -days "$DAYS_SRV" -sha256 -extfile "$SRV_CNF" -extensions req_ext >/dev/null 2>&1
  rm -f "$SRV_CSR"
else
  echo "[certgen] Cert serwera już istnieje"
fi

chmod 0600 "$CA_KEY" || true
chmod 0644 "$CA_CRT" "$SRV_CRT" "$SRV_KEY" || true

if [ -n "$CLIENT_CN_LIST" ]; then
  echo "$CLIENT_CN_LIST" | tr ',' '\n' | while read -r CN; do
    CN_TRIM="$(echo "$CN" | tr -d '[:space:]')"
    [ -z "$CN_TRIM" ] && continue
    C_KEY="$CERTS_DIR/clients/${CN_TRIM}.key"
    C_CSR="$CERTS_DIR/clients/${CN_TRIM}.csr"
    C_CRT="$CERTS_DIR/clients/${CN_TRIM}.crt"
    if [ -f "$C_KEY" ] && [ -f "$C_CRT" ]; then
      echo "[certgen] Klient ${CN_TRIM} już istnieje"
      continue
    fi
    echo "[certgen] Generuję klienta ${CN_TRIM}…"
    openssl genrsa -out "$C_KEY" 2048 >/dev/null 2>&1
    openssl req -new -key "$C_KEY" -subj "/C=PL/O=IoTLab/CN=${CN_TRIM}" -out "$C_CSR" >/dev/null 2>&1
    openssl x509 -req -in "$C_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial -out "$C_CRT" -days "$DAYS_SRV" -sha256 -extfile /dev/stdin >/dev/null 2>&1 <<EOF
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
EOF
    rm -f "$C_CSR"
    chmod 0644 "$C_KEY" "$C_CRT" || true
  done
fi

echo "[certgen] Pliki w $CERTS_DIR:"
ls -l "$CERTS_DIR" || true
echo "[certgen] Pliki w $CERTS_DIR/clients:"
ls -l "$CERTS_DIR/clients" || true
