#!/bin/bash

cd /etc/ssl/etcd/ssl

/usr/local/bin/cfssl gencert --initca=true /etc/ssl/etcd/config/ca-csr.json | /usr/local/bin/cfssljson -bare ca -

/usr/local/bin/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/ssl/etcd/config/ca-config.json -profile=server /etc/ssl/etcd/config/server-csr.json | /usr/local/bin/cfssljson -bare server

/usr/local/bin/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/ssl/etcd/config/ca-config.json -profile=client /etc/ssl/etcd/config/client-csr.json | /usr/local/bin/cfssljson -bare client

/usr/local/bin/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=/etc/ssl/etcd/config/ca-config.json -profile=peer /etc/ssl/etcd/config/peer-csr.json | /usr/local/bin/cfssljson -bare peer



