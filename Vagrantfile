# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "puppetlabs/centos-7.2-64-nocm"

  config.vm.define "stepup-build" do |conf|
    # Prevent port "2222" in use error which Vagrant is unable auto correct by choosing a ssh port randomly
    r = Random.new
    ssh_port = r.rand(1000...5000)
    config.vm.network "forwarded_port", guest: 22, host: "#{ssh_port}", id: 'ssh', auto_correct: true

    conf.vm.hostname = "stepup-build"
    conf.vm.provider "vmware_fusion" do |v|
      v.vmx["memsize"] = "8192"
      v.vmx["numvcpus"] = "1"
      # puppetlabs centos box uses ens33 nic
      v.vmx["ethernet0.pciSlotNumber"] = "33"
    end
    config.vm.provider "virtualbox" do |v|
      v.memory = 8192
    end
  end

  config.vm.provision "ansible" do |ansible|
    ansible.compatibility_mode = "2.0"
    ansible.playbook = "build.yml"
  end

end
