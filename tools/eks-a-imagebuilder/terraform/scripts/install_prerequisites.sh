# https://github.com/deepakm-ntnx/eks-anywhere-build-tooling/tree/main/projects/kubernetes-sigs/image-builder#building-your-own-image
sudo apt update -y
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin unzip ansible -y
sudo usermod -a -G kvm ubuntu
sudo chown root:kvm /dev/kvm
sudo snap install yq
sudo apt install jq