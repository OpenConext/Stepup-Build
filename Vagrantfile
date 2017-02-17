# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "puppetlabs/centos-7.2-64-nocm"

  config.vm.define "stepup-build" do |conf|
    conf.vm.hostname = "stepup-build"
    conf.vm.provider "vmware_fusion" do |v|
      v.vmx["memsize"] = "1024"
      v.vmx["numvcpus"] = "1"
      # puppetlabs centos box uses ens33 nic
      v.vmx["ethernet0.pciSlotNumber"] = "33"
    end
    config.vm.provider "virtualbox" do |v|
      v.memory = 1024
    end
  end

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "build.yml"
  end

end
