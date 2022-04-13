git clone https://github.com/aws/eks-anywhere-build-tooling.git
cd eks-anywhere-build-tooling/projects/kubernetes-sigs/image-builder
export BASE_IMAGE=nutanix-ubuntu-eks-a
export RELEASE_BRANCH=1-21
export RHSM_USER=testuser
export RHSM_PASS=testpwd
export ARTIFACTS_BUCKET=s3://projectbuildpipeline-857-pipelineoutputartifactsb-10ajmk30khe3f
make build-qemu-rhel-local