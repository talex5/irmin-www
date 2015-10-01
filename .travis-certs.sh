#!/bin/bash -eux
make -f Makefile.user conf/tls/server.key
touch conf/tls/server.pem
