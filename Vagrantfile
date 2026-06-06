Vagrant.configure("2") do |config|
  config.vm.define "target" do |target|
    target.vm.box = "bento/ubuntu-24.04"
    target.vm.hostname = "target-node"
    target.vm.network "private_network", ip: "192.168.56.10"
    target.vm.network "forwarded_port", guest: 80, host: 8080, auto_correct: true
    target.vm.provision "shell", path: "scripts/provision-target.sh"
    target.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
  end

  config.vm.define "runner" do |runner|
    runner.vm.box = "bento/ubuntu-24.04"
    runner.vm.hostname = "github-runner"
    runner.vm.network "private_network", ip: "192.168.56.20"
    runner.vm.provision "shell", path: "scripts/provision-runner.sh"
    runner.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
    end
  end
end
