#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KEY_DIR="$SCRIPT_DIR/keys"
mkdir -p "$KEY_DIR"

OPENSSL_CNF="$KEY_DIR/openssl.cnf"

cat > "$OPENSSL_CNF" <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = github.com

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash

[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = github.com
DNS.2 = www.github.com
DNS.3 = gist.github.com
DNS.4 = api.github.com
DNS.5 = codeload.github.com
DNS.6 = raw.githubusercontent.com
DNS.7 = objects.githubusercontent.com
DNS.8 = github-releases.githubusercontent.com
DNS.9 = *.github.com
DNS.10 = *.githubusercontent.com
IP.1 = 127.0.0.1
EOF

openssl genrsa -out "$KEY_DIR/ca.key" 4096
openssl req -x509 -new -nodes \
    -key "$KEY_DIR/ca.key" \
    -sha256 \
    -days 3650 \
    -out "$KEY_DIR/ca.pem" \
    -subj "/CN=0proxy local CA" \
    -extensions v3_ca \
    -config "$OPENSSL_CNF"

openssl genrsa -out "$KEY_DIR/private_key.pem" 2048
openssl req -new \
    -key "$KEY_DIR/private_key.pem" \
    -out "$KEY_DIR/server.csr" \
    -config "$OPENSSL_CNF"
openssl x509 -req \
    -in "$KEY_DIR/server.csr" \
    -CA "$KEY_DIR/ca.pem" \
    -CAkey "$KEY_DIR/ca.key" \
    -CAcreateserial \
    -out "$KEY_DIR/cert.pem" \
    -days 3650 \
    -sha256 \
    -extensions v3_req \
    -extfile "$OPENSSL_CNF"

rm -f "$KEY_DIR/server.csr"
