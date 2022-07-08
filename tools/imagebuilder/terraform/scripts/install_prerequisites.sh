# https://image-builder.sigs.k8s.io/capi/providers/raw.html
sudo apt-get -y update
sudo apt install -y git unzip make python3-pip qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin
sudo usermod -a -G kvm ${USER}
sudo chown root:kvm /dev/kvm

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install packer
packer --version

sudo pip install --upgrade pip

# exit and log back in to make the change take place.
exit 0