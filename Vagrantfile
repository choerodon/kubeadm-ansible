# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|

(1..3).each do |i|
    config.vm.define "node#{i}" do |s|
    s.vm.box = "bento/centos-7.3"
    s.vm.box_url = "http://file.choerodon.com.cn/vagrant/box/bento_centos-7.3.box"
    s.vm.hostname = "node#{i}"
    n = 10 + i
    s.vm.network "private_network", ip: "192.168.56.#{n}"
    s.vm.provider "virtualbox" do |v|
        v.memory = 3072
        v.cpus = 4
    end
    end
end

if Vagrant.has_plugin?("vagrant-cachier")
    config.cache.scope = :box
end

end