#!/bin/sh

ROOT=${1:-/var/www}
SNI=server
DST=$ROOT/certs

[ -d $DST ] || mkdir -p $DST

openssl req -new -nodes -x509 -days 1825 -config $ROOT/selfsign.cnf -out $DST/$SNI.cert -keyout $DST/$SNI.key
cat $DST/$SNI.cert $DST/$SNI.key | tee $DST/$SNI.pem
chmod 0644 $SNI.key
# openssl x509 -in $DST/$SNI.cert -text -noout
