# dashboard

## 访问设置

###  使用ip地址访问

1、 编辑`kubernetes-dashboard`的service配置，添加externalIPs，并修改绑定到任意节点的ip上。

```
kubectl edit svc kubernetes-dashboard -n kube-system
```

修改端口为8443,并将`<YOUR_HOST_IP>`替换为任意节点的ip

```
...
  externalIPs:
  - <YOUR_HOST_IP>
  ports:
  - port: 8443
    protocol: TCP
    targetPort: 8443
  selector:
    k8s-app: kubernetes-dashboard
...
```
通过`https://<YOUR_HOST_IP>:8443`访问。

###  使用域名访问

1、 首先，阅读TSL配置,创建dashboard域名证书的secret(在kube-system命名空间下),或如果设置了全局泛域名的证书配置参考第3点。

2、 根据域名创建ingress,替换掉`dashboard.example.com`为访问域名,`<SecretName>`为上一步创建的secret的名称。

```
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
    secretName: <SecretName>
  rules:
  - host: dashboard.example.com
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 443
```

3、 如果设置了全局泛域名的证书配置,直接应用下边的配置,注意替换`dashboard.example.com`为想要访问的域名,确保该域名在证书中已签名。或者如果你不在乎浏览器检测不安全情况,可以不配置证书，使用ingress-nginx-controller默认自签名证书。也可以这样部署,`dashboard.example.com`替换为访问的域名:

```
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

通过域名`https://dashboard.example.com`访问。

##  账号管理

### 主要思路：

- 生成服务账号
- 在某个命令空间创建角色,并分配角色权限
- 将角色与服务账号绑定

### 示例参考：

集群管理员：

```
# 创建部署文件
cat > dashboard-admin-role.yml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin
  labels:
    devops-app: devops-account
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard-admin
  namespace: kube-system
EOF

# 部署
kubectl apply -f dashboard-admin-role.yml
# 查看token
kubectl get secret -n kube-system | grep dashboard-admin | awk '{print $1}' | xargs kubectl describe secret -n kube-system
```

如果只针对某个命令空间授权：

```
# 创建配置文件,以hitsm为例
cat > dashboard-hitsm-member1.yml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hitsm-member1
  namespace: hitsm
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: hitsm-role1
  namespace: hitsm
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: hitsm-role1-member1
  namespace: hitsm
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: hitsm-role1
subjects:
- kind: ServiceAccount
  name: hitsm-member1
  namespace: hitsm
EOF
```

如果只给某个命令空间的读pod的权限：

```
# 修改角色权限
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: pod-reader
  namespace: <Namespace>
rules:
- apiGroups:
  - '*'
  resources:
  - 'pods'
  - 'pods/log'
  verbs:
  - 'get'
  - 'list'
```



