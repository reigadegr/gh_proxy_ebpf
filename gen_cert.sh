#!/bin/sh
# 安装
# apt install openssl openssl-tool

# 生成私钥
openssl genpkey -algorithm ED25519 -out keys/private_key.pem

# 从私钥导出公钥
openssl req -new -x509 -key keys/private_key.pem -out keys/cert.pem -days 3650 -subj "/CN=github.com"
