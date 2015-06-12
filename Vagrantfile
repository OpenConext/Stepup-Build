# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.hostname = "stepup-build"
  config.vm.box = "puppetlabs/centos-7.0-64-nocm"

  config.vm.provider "vmware_fusion" do |v|
    v.vmx["memsize"] = "1024"
  end
  config.vm.provider "virtualbox" do |v|
    v.memory = 1024
  end

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "build.yml"
  end

end
