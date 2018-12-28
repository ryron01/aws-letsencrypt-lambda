#!/bin/bash
set -e

virtualenv venv && source venv/bin/activate

pip install certbot certbot-dns-route53
cp /lambda/fetch_cert.py venv/lib/python2.7/site-packages/fetch_cert.py
cd venv/lib/python2.7/site-packages

zip -r9 /lambda/fetch_cert.zip *