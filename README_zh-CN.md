|![](https://upload.wikimedia.org/wikipedia/commons/thumb/1/17/Warning.svg/156px-Warning.svg.png) | 此仓库已停止更新，没有计划支持任何新功能。新的项目地址为 [open-hand/kubeadm-ha](https://github.com/open-hand/kubeadm-ha)
|---|---|

## 1. 环境准备

> 注意：目前只支持centos 7.2+

在要执行ansible脚本的机器上安装ansible运行需要的环境：

```
sudo yum install epel-release -y 
sudo yum install git python36 sshpass -y
sudo python3.6 -m ensurepip
sudo /usr/local/bin/pip3 install --no-cache-dir ansible==2.7.5 netaddr -i https://mirrors.aliyun.com/pypi/simple/
```

克隆项目：

```
git clone https://github.com/choerodon/kubeadm-ansible.git
```

## 2. 修改hosts

 编辑项目下的`inventory/hosts`文件,修改各机器的访问地址、用户名、密码，并维护好各节点与角色的关系,前面的名称为机器的hostname。该用户必须是具有root权限的用户。

 > 注意：etcd节点和master节点需要在相同的机器。

 比如,想要部署单节点集群,只需要这样配置(参考)：

 ```
[all]
node1 ansible_host=192.168.56.11 ansible_user=root ansible_ssh_pass=change_it ansible_become=true

[kube-master]
node1

[etcd]
node1

[kube-node]
node1

 ```

## 3. 修改变量

编辑项目下的`inventory/vars`文件,修改变量`k8s_interface`的值为要部署机器的ipv4的网卡名称(centos默认是eth0),如果不确定可使用`ifconfig`命令查看。

```
k8s_interface: "eth0"
```
注意:如果各个机器之间网卡名称不一致,请将`k8s_interface`变量从`inventory/vars`文件删掉，并在`inventory/host`文件中给每个机器加上ip地址，比如:

```
[all]
node1 ansible_host=192.168.56.11 ip=192.168.56.11 ansible_user=root ansible_ssh_pass=change_it ansible_become=true
...
...
```

如果所有机器以`代理的方式`访问外网,请配置以下几个变量,否则请不要配置:

```
http_proxy: http://1.2.3.4:3128
https_proxy: http://1.2.3.4:3128
no_proxy: localhost,127.0.0.0/8
docker_proxy_enable: true
```

## 4. 部署

> 如果在阿里云上部署先阅读第7点

执行:

```
ansible-playbook -i inventory/hosts -e @inventory/vars cluster.yml
```

查看等待pod的状态为runnning:

```
kubectl get po -n kube-system
```

如果部署失败，想要重置集群(所有数据),执行：

```
ansible-playbook -i inventory/hosts reset.yml
```

## 5. Ingress TSL配置

参考:[TSL配置说明](docs/ingress-nginx.md)

## 6. Dashboard 配置

参考:[Dashboard配置说明](docs/dashboard.md)

## 7. 阿里云部署

### 修改Hostname(*)

在阿里云的ECS的控制面板上修改ECS实例的hostname,名称最好只包含小写字母、数字和中划线。并保持与`inventory/hosts`中的名称与ECS控制台上的名称保持一致,重启生效。

### 网段选择(*)

如果ECS服务器用的是专有网络,pod和service的网段不能与vpc网段重叠，示例参考：

```
# 如果vpc网段为`172.*`
kube_pods_subnet: 192.168.0.0/20
kube_service_addresses: 192.168.255.0/20

# 如果vpc网段为`10.*`
kube_pods_subnet: 172.16.0.0/16
kube_service_addresses: 172.19.0.0/20

# 如果vpc网段为`192.168.*`
kube_pods_subnet: 172.16.0.0/16
kube_service_addresses: 172.19.0.0/20

```

### flannel类型(*)

在使用VPC网络的ECS上部署k8s时，flannel网络的Backend类型需要是`ali-vpc`。在本脚本中默认使用的是`vxlan`类型，虽然在vpc环境下网络能通,但是不稳定波动较大。所以推荐使用`ali-vpc`的类型。

因此,首先需要设置默认的flannel网络不安装，通过在`inventory/vars`文件中添加变量：

```
flannel_enable: false
```

跑完ansible脚本后手动安装flannel网络插件,在其中一个master节点创建配置文件`kube-flannel-aliyun.yml`:

```
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
rules:
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes/status
    verbs:
      - patch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flannel
  namespace: kube-system
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-system
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "type": "flannel",
      "delegate": {
        "isDefaultGateway": true
      }
    }
  net-conf.json: |
    {
      "Network": "[PodsSubnet]",
      "Backend": {
        "Type": "ali-vpc"
      }
    }
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-system
  labels:
    tier: node
    app: flannel
spec:
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      hostNetwork: true
      nodeSelector:
        beta.kubernetes.io/arch: amd64
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni
        image: registry.cn-hangzhou.aliyuncs.com/google-containers/flannel:v0.9.0
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conf
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: registry.cn-hangzhou.aliyuncs.com/google-containers/flannel:v0.9.0
        command: [ "/opt/bin/flanneld", "--ip-masq", "--kube-subnet-mgr" ]
        securityContext:
          privileged: true
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: ACCESS_KEY_ID
          value: [YOUR_ACCESS_KEY_ID]
        - name: ACCESS_KEY_SECRET
          value: [YOUR_ACCESS_KEY_SECRET]
        volumeMounts:
        - name: run
          mountPath: /run
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      volumes:
        - name: run
          hostPath:
            path: /run
        - name: cni
          hostPath:
            path: /etc/cni/net.d
        - name: flannel-cfg
          configMap:
            name: kube-flannel-cfg
```

请注意修改配置中的参数值：

- `Network`：为pod网段。

- `ACCESS_KEY_ID`:必填

- `ACCESS_KEY_SECRET`:必填

该ACCESS_KEY的用户需要拥有以下权限：

- 只读访问云服务器(ECS)的权限
- 管理专有网络(VPC)的权限

然后使用kubectl命令部署,部署成功后在vpc的路由表中会添加多条路由条目,下一跳分别为每个节点的pod ip段：

```
kubectl apply -f kube-flannel-aliyun.yml
```

接下来需要在ECS安全组，在入方向规则中加上pod网段的地址。否则在pod容器中无法访问别的节点的pod的端口,比如:

授权策略 | 协议类型 | 端口范围 | 授权类型 | 授权对象 | ...
---|---|---|---|---|---
允许 | 全部 | -1/-1 | 地址段访问 | 192.168.0.0/20 | ...


###  绑定云盘存储

一般情况下，我们pv都是使用nfs进行存储的，但是读写效率不是很高，对于有高读写性能要求的可以配置云盘作为挂载卷。

如果想要使用aliyun的云盘存储,还需要部署aliyun-controller组件。

首先,在`所有节点`执行以下命令，将`aliyun-flexv`二进制文件拷贝到kubele插件目录下:

```
FLEXPATH=/usr/libexec/kubernetes/kubelet-plugins/volume/exec/aliyun~flexv; 
sudo mkdir $FLEXPATH -p; 
docker run --rm -v $FLEXPATH:/opt registry.aliyuncs.com/kubeup/kube-aliyun cp /flexv /opt/
```

然后,修改本项目下的`roles/addons/kubeup`下的`aliyun-controller.yml`文件，并给相关变量填上相应的值,如果不确定可登陆aliyun相应管理控制台查看或在服务器上请求该地址查询`curl --retry 5 -sSL http://100.100.100.200/latest/meta-data/{{META_ID}}`。

`--cluster-cidr`: pod的ip段

`ALIYUN_ACCESS_KEY`: 阿里云的API访问key

`ALIYUN_ACCESS_KEY_SECRET`: 阿里云的API访问秘钥

`ALIYUN_ZONE`: 云服务器ECS所在可用区id

`ALIYUN_ROUTER`: 专有网络vpc的路由id

`ALIYUN_ROUTE_TABLE`: 专有网络vpc的路由表id

`ALIYUN_REGION`: 云服务器ECS所在区域id

`ALIYUN_VPC`: 专有网络vpc的id

`ALIYUN_VSWITCH`: 专有网络vpc的交换机id


填好变量后，将改上边文件拷贝到所有master节点的`/etc/kubernetes/manifests/`下。

该ACCESS_KEY的用户需要拥有以下权限：

- 只读访问云服务器(ECS)的权限
- 管理专有网络(VPC)的权限

编辑所有master节点下的`/etc/kubernetes/manifests/kube-controller-manager.yaml`文件。在command命令中添加如下两个命令和环境变量:

command:

```
--allocate-node-cidrs=true
--configure-cloud-routes=false
```

环境变量:

```
env:
- name: ALIYUN_ACCESS_KEY
  value: [YOUR_ALIYUN_ACCESS_KEY]
- name: ALIYUN_ACCESS_KEY_SECRET
  value: [YOUR_ALIYUN_ACCESS_KEY_SECRET]
```

重启所有master节点的kubelet:

```
systemctl restart kubelet
```

检查kube-controller是否健康:

```
kubectl get po -n kube-system | grep aliyun-controller
```

绑定云盘示例,每个云盘只能绑定一次：

```
# 使用pv绑定,diskId为云盘的id
kind: PersistentVolume
apiVersion: v1
metadata:
  name: test-pv-volume
  labels:
    type: flexVolume
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  flexVolume:
    driver: "aliyun/flexv"
    fsType: "ext4"
    options:
      diskId: "d-bp1i23j39i30if"

# pod直接绑定

apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: test
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: test
    flexVolume:
      driver: "aliyun/flexv"
      fsType: "ext4"
      options:
        diskId: "d-1ierokwer8234jowe"
```

## 8. 刷新集群证书

> 刷新证书的前提需要保证CA根证书存在，证书刷新后会重启master节点 kubelet 以应用新的证书，届时可能导致1-2分钟无法操作集群，但业务应用是不受影响的。

```
ansible-playbook -i inventory/hosts -e @inventory/vars renew-certs.yml
```