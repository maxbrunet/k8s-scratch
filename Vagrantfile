$num_instances = 1
$instance_name_prefix = "k8s-scratch"
$subnet = "192.168.183"

Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/xenial64"
    (1..$num_instances).each do |i|
        config.vm.define vm_name = "%s-%01d" % [$instance_name_prefix, i] do |node|
            node.vm.hostname = vm_name
            ip = "#{$subnet}.#{100+i}"
            node.vm.network :private_network, ip: ip
            
            node.vm.provision "shell", path: "k8s-scratch.sh", run: "always"
        end
    end
end
