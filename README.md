|![](https://upload.wikimedia.org/wikipedia/commons/thumb/1/17/Warning.svg/156px-Warning.svg.png) | This project is no longer supported,There is no plan to support any new features.The successor is [open-hand/kubeadm-ha](https://github.com/open-hand/kubeadm-ha)
|---|---|

# Kubeadmin Ansible [中文](README_zh-CN.md)

Kubeadmin ansible is a toolkit for simple and quick installing k8s cluster. 

## 1. Environmental preparation

>Note: Currently only centos 7.2+ is supported

Install the ansible run environment on the machine where the ansible script is to be executed:

```
sudo yum install epel-release -y 
sudo yum install git python36 sshpass -y
sudo python3.6 -m ensurepip
sudo /usr/local/bin/pip3 install --no-cache-dir ansible==2.7.5 netaddr
```

Clone project：

```
git clone https://github.com/choerodon/kubeadm-ansible.git
```

## 2. Modify hosts

 Edit the `inventory/hosts` file under the toolkit, modify the access address, user name, and password of each machine and maintain the relationship between each node and role. The front name is the hostname of the machine. The user must have root privileges.

 > Note: The `etcd` node and the `master` node need to be on the same machine.

 For example, if deploy a single-node cluster, configure it (reference):

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

## 3. Modify the variable

Edit the `inventory/vars` file under the toolkit, and change the value of `k8s_interface` to the name of the ipv4 NIC (centos defaults to eth0). If not sure, use the `ifconfig` command to check it.

```
k8s_interface: "eth0"
```
Note: If the names of the network card are not the same between the machines, delete the `k8s_interface` variable from the `inventory/vars` file and add an IP address to each machine in the `inventory/host` file. For example:
```
[all]
node1 ansible_host=192.168.56.11 ip=192.168.56.11 ansible_user=root ansible_ssh_pass=change_it ansible_become=true
...
...
```

If all machines access the external network as `proxy', please configure the following variables, otherwise do not configure:

```
http_proxy: http://1.2.3.4:3128
https_proxy: http://1.2.3.4:3128
no_proxy: localhost,127.0.0.0/8
docker_proxy_enable: true
```

## 4. Deploy

> If deploy on Alibaba Cloud, please read **Alibaba Cloud Deployment** first in this page.

Execute:

```
ansible-playbook -i inventory/hosts -e @inventory/vars cluster.yml
```

View the status of the waiting pod for running:

```
kubectl get po -n kube-system
```

If the deployment fails and you want to reset the cluster (all data), execute:

```
ansible-playbook -i inventory/hosts reset.yml
```

## 5. Ingress TSL configuration

Reference: [TSL Configuration Notes] (docs/ingress-nginx.md)

## 6. Dashboard configuration

Reference: [Dashboard configuration instructions] (docs/dashboard.md)

## 7. Alibaba Cloud Deployment

### Modify Hostname(*)

Modify the hostname of the ECS instance on the control panel of ECS. The name should preferably contain only lowercase letters, numbers, and dash. And keep consistent with the name in the ʻinventory/hosts` and the name of ECS console, restart to take effect.

### Segment selection (*)

If the ECS server uses a private network, the segments of pod and service cannot overlap with the VPC segment. For example, refer to:
```

# If the vpc segment is `172.*`
kube_pods_subnet: 192.168.0.0/20
kube_service_addresses: 192.168.255.0/20

# If the vpc segment is `10.*`
kube_pods_subnet: 172.16.0.0/16
kube_service_addresses: 172.19.0.0/20

# If the vpc segment is `192.168.*`
kube_pods_subnet: 172.16.0.0/16
kube_service_addresses: 172.19.0.0/20

```

### Flannel type (*)

When deploying k8s on an ECS using a VPC network, the backend type of the flannel network needs to be `ali-vpc`. By default, the `vxlan` type is used in this script. Although the network is able to communicate in the VPC environment, the instability fluctuates. So it is recommended to use the `ali-vpc` type.

Therefore, set the default flannel network to not be installed by adding variables in the `inventory/vars` file:

```
flannel_enable: false
```

After running the ansible script, manually install the flannel network plugin and create the configuration file `kube-flannel-aliyun.yml` on one of the master nodes:

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

Please pay attention to modify the parameter value in the configuration:

- `Network`：The network segment of Pod.

- `ACCESS_KEY_ID`: Required

- `ACCESS_KEY_SECRET`: Required

The`ACCESS_KEY` user has the following permissions:

- Read-only access to cloud server (ECS) permissions
- Manage Permissions for a Private Network (VPC)

Then use the `kubectl` command to deploy. After the deployment is successful, multiple route entries have been added to the routing table of the VPN. The next hop is the pod IP segment of each node.

```
kubectl apply -f kube-flannel-aliyun.yml
```

Next, in the ECS security group, add the address of the pod network segment in the inbound rule. Otherwise, the ports of other nodes' pods cannot be accessed in the pod container. For example:

Authorization Policy | Protocol Type | Port Range | Authorization Type | Authorization Object | ...
---|---|---|---|---|---
Allow | All | -1/-1 | Address Segment Access | 192.168.0.0/20 | ...



###  Binding Cloud Storage

Under normal circumstances, `pv` are stored using `nfs`, but the efficiency of reading and writing is not very high, for `pv` with high performance requirements for reading and writing, you can configure the cloud disk as a mount volume.

If use aliyun cloud storage, also need to deploy `aliyun-controller` components.

First, execute the following command on `all nodes`. Copy the `aliyun-flexv` binary file into the kubele plugin directory:

```
FLEXPATH=/usr/libexec/kubernetes/kubelet-plugins/volume/exec/aliyun~flexv; 
sudo mkdir $FLEXPATH -p; 
docker run --rm -v $FLEXPATH:/opt registry.aliyuncs.com/kubeup/kube-aliyun cp /flexv /opt/
```

Then, modify the `aliyun-controller.yml` file under `roles/addons/kubeup` under this project, and fill in the relevant values with the relevant variables. If are not sure, log in to aliyun to view the corresponding management console, or request the address on the server to query `curl --retry 5 -sSL http://100.100.100.200/latest/meta-data/{{META_ID}}`.

`--cluster-cidr`: IP section of pod

`ALIYUN_ACCESS_KEY`: The API Access Key of Alibaba Cloud

`ALIYUN_ACCESS_KEY_SECRET`: The API Access Key of Alibaba Cloud

`ALIYUN_ZONE`: Availability id of cloud server ECS

`ALIYUN_ROUTER`: Private network vpc routing id

`ALIYUN_ROUTE_TABLE`: Private network vpc routing id

`ALIYUN_REGION`: Availability id of cloud server ECS

`ALIYUN_VPC`: Private network vpc routing id

`ALIYUN_VSWITCH`: The switch id of private network vpc


After filling in the variables, copy the above file to `/etc/kubernetes/manifests/` of all master nodes.

The ACCESS_KEY user has the following permissions:

- Read-only access to cloud server (ECS) permissions
- Manage Permissions for a Private Network (VPC)

Edit the `/etc/kubernetes/manifests/kube-controller-manager.yaml` file under all master nodes. Add the following two commands and environment variables in the command command:

command:

```
--allocate-node-cidrs=true
--configure-cloud-routes=false
```

Environment variables:

```
env:
- name: ALIYUN_ACCESS_KEY
  value: [YOUR_ALIYUN_ACCESS_KEY]
- name: ALIYUN_ACCESS_KEY_SECRET
  value: [YOUR_ALIYUN_ACCESS_KEY_SECRET]
```

Restart all the kubelets of the master node:

```
systemctl restart kubelet
```

Check if the kube-controller is healthy:
```
kubectl get po -n kube-system | grep aliyun-controller
```

Bind the examples of cloud disk , each cloud disk can only be bound once:

```
# Using pv binding, diskId is the id of the cloud disk
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

# Directly bind pod

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

## Reporting issues

If you find any shortcomings or bugs, please describe them in the [issue](https://github.com/choerodon/choerodon/issues/new?template=issue_template.md).

## How to contribute
Pull requests are welcome! Follow [this link](https://github.com/choerodon/choerodon/blob/master/CONTRIBUTING.md) for more information on how to contribute.
Pull requests are welcome! Follow [this link](https://github.com/choerodon/choerodon/blob/master/CONTRIBUTING.md) for more information on how to contribute.


## 8. Refresh cluster certificate

> The prerequisite for refreshing the certificate is to ensure that the CA root certificate exists. After the certificate is refreshed, the master node kubelet is restarted to apply the new certificate. At this time, the cluster may not be operated for 1-2 minutes, but the business application is not affected.

```
ansible-playbook -i inventory/hosts -e @inventory/vars renew-certs.yml
```
