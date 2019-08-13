# k8s-scratch

A minimalist script to bootstrap a [Kubernetes][k8s.io] cluster for learning purpose.

No [`kubeadm`][kubeadm] or other bootstrapping tool ([`kops`][kops], [`kubespray`][kubespray], etc, ...), no Cloud provider (AWS, GCP), only a self-contained Bash script and [`vagrant`][vagrant] + [VirtualBox][virtualbox].

* Environment:
  * Ubuntu 16.04
  * Kubernetes 1.12
* The project follows the official documentation [Creating a Custom Cluster from Scratch][scratch]
* Automation is purposely minimal → 1 self-contained shell script simply chaining commands
* All commands should have a link to [docs.k8s.io][docs.k8s.io], unless out of K8s scope (e.g. Docker, Ubuntu/Debian) then a link to the third-party documentation
* No cloud provider → [Vagrant][vagrant] + [VirtualBox][virtualbox]
* Iterations:
  * [x] Bootstrap a single-node cluster
  * [ ] Bootstrap a 3-node cluster with 1 master
  * [ ] Bootstrap a 3-node cluster with 3 masters
  * [ ] Then we might play a bit:
    * [ ] Add a few more SSL certs
    * [ ] Add a network plugin (e.g. Calico, Flannel)
    * [ ] Spread services across more VMs
    * [ ] Etc...

## Usage

Test the script using [`vagrant`][vagrant]:

```shell
vagrant up
vagrant ssh
```

[k8s.io]: https://k8s.io
[kubeadm]: https://v1-12.docs.kubernetes.io/docs/setup/independent/create-cluster-kubeadm/
[kops]: https://github.com/kubernetes/kops
[kubespray]: https://github.com/kubernetes-sigs/kubespray
[vagrant]: https://www.vagrantup.com
[virtualbox]: https://www.virtualbox.org
[scratch]: https://v1-12.docs.kubernetes.io/docs/setup/scratch/
[docs.k8s.io]: https://docs.k8s.io
