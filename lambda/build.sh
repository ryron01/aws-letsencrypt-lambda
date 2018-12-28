#!/bin/bash
set -e

virtualenv venv && source venv/bin/activate

pip install certbot certbot-dns-route53
cd venv/lib/python2.7/site-packages

zip -r9 /lambda/fetch_cert.zip .
zip -g /lambda/fetch_cert.zip ../../../../lambda/fetch_cert.py