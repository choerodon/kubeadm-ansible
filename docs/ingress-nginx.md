# Ingress Nginx Controller

## TSL配置

 1、购买或生成域名证书。

 2、 配置集群默认的域名证书到ingress-nginx-controller,如果在ingress的tsl不指定secret，则使用默认。

首先，根据证书生成secret，参考一下命令：

```
kubectl create secret tls ingress-secret --key xxx.pem --cert xxx.pem -n kube-system
```

在第一台master节点,修改文件`/etc/kubernetes/addons/ingress-nginx/with-rbac.yml`中`nginx-ingress-controller`的容器参数，添加一条：

```
- --default-ssl-certificate=$(POD_NAMESPACE)/ingress-secret
```

然后将该部署文件重新应用：

```
kubectl apply -f /etc/kubernetes/addons/ingress-nginx/with-rbac.yml -n kube-system
```

3、 如果并不想配置全局默认的域名证书 或者 使用与默认域名不同的其他域名配置到ingress

首先，创建secret，但是一个secret只能配置给某一个ingress，并要求在同一个namespaces下：

```
kubectl create secret tls <SecretName> --key xxx-key.pem --cert xxx.pem -n <Namespaces>
```

参考下边修改部署配置，创建Ingress:

```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: app01-ingress
  namespace: <Namespaces>
spec:
  tls:
  - hosts:
    - <YOUR_DNS_ADDRESS>
    secretName: <SecretName>
  rules:
  - host: <YOUR_DNS_ADDRESS>
    http:
      paths:
      - backend:
          serviceName: <ServiceName>
          servicePort: <Port>
```

- `xxx-key.pem`: 私钥。
- `xxx.pem`: 证书。
- `<SecretName>` : 替换为想要创建的secret的名字。
- `<Namespaces>` : 替换为要部署的命名空间名称。
- `<YOUR_DNS_ADDRESS>` : 替换为想要解析到该应用的域名地址。
- `<ServiceName>`: 应用的service名称。
- `<Port>`: 应用的service端口。


## 测试示例(仅供参考,勿直接运行)

http访问测试：

```
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: registry.cn-hangzhou.aliyuncs.com/choerodon-tools/nginx:1.11.4-alpine
          ports:
            - containerPort: 80
              protocol: TCP
          resources:
            limits:
              memory: 250Mi
            requests:
              memory: 250Mi
          terminationMessagePath: /dev/termination-log
          imagePullPolicy: IfNotPresent
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      securityContext: {}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 2

---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
  selector:
    app: nginx
  type: ClusterIP
  sessionAffinity: None
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx
spec:
  rules:
  - host: nginx.example.com
    http:
      paths:
      - backend:
          serviceName: nginx
          servicePort: 80
```


https代理到http后台应用测试：

```
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx
spec:
  tls:
  - hosts:
    - nginx.example.com
  rules:
  - host: nginx.example.com
    http:
      paths:
      - backend:
          serviceName: nginx
          servicePort: 80
```


后台应用只能使用https访问测试：

```
# 注意添加如下annotations
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dashboard
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: "nginx"
    ingress.kubernetes.io/ssl-passthrough: "true"
    ingress.kubernetes.io/secure-backends: "true"
spec:
  tls:
  - hosts:
    - dashboard.example.com
  rules:
  - host: dashboard.example.com
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 443
```


[[官方github地址](https://github.com/kubernetes/ingress-nginx)]