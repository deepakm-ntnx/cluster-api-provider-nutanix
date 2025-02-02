SHELL := bash
GOCMD=go
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOTOOL=$(GOCMD) tool
EXPORT_RESULT?=false # for CI please set EXPORT_RESULT to true
# Image URL to use all building/pushing image targets
IMG ?= ghcr.io/nutanix-cloud-native/cluster-api-provider-nutanix/controller:latest

# Extract base and tag from IMG
IMG_REPO ?= $(word 1,$(subst :, ,${IMG}))
IMG_TAG ?= $(word 2,$(subst :, ,${IMG}))
LOCAL_PROVIDER_VERSION ?= ${IMG_TAG}
ifeq (${IMG_TAG},)
IMG_TAG := latest
endif

ifeq (${LOCAL_PROVIDER_VERSION},latest)
# TODO(release-blocker): Change this versions after release when required here and in e2e config (test/e2e/config/nutanix.yaml)
LOCAL_PROVIDER_VERSION := v1.4.99
endif

# PLATFORMS is a list of platforms to build for.
PLATFORMS ?= linux/amd64,linux/arm64,linux/arm
PLATFORMS_E2E ?= linux/amd64

# KIND_CLUSTER_NAME is the name of the kind cluster to use.
KIND_CLUSTER_NAME ?= capi-test

# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.29

#
# Directories.
#
# Full directory of where the Makefile resides
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
REPO_ROOT := $(shell git rev-parse --show-toplevel)
EXP_DIR := exp
TEST_DIR := test
E2E_DIR ?= ${REPO_ROOT}/test/e2e
TEMPLATES_DIR := templates
E2E_FRAMEWORK_DIR := $(TEST_DIR)/framework
CAPD_DIR := $(TEST_DIR)/infrastructure/docker
GO_INSTALL := $(REPO_ROOT)/scripts/go_install.sh
NUTANIX_E2E_TEMPLATES := ${E2E_DIR}/data/infrastructure-nutanix
RELEASE_DIR ?= $(REPO_ROOT)/out

# CNI paths for e2e tests
CNI_PATH_CALICO ?= "${E2E_DIR}/data/cni/calico/calico.yaml"
CNI_PATH_FLANNEL ?= "${E2E_DIR}/data/cni/flannel/flannel.yaml" # From https://github.com/flannel-io/flannel/blob/master/Documentation/kube-flannel.yml
CNI_PATH_CILIUM ?= "${E2E_DIR}/data/cni/cilium/cilium.yaml" # helm template cilium cilium/cilium --version 1.13.0 -n kube-system --set hubble.enabled=false --set cni.chainingMode=portmap  --set sessionAffinity=true | sed 's/${BIN_PATH}/$BIN_PATH/g'
CNI_PATH_CILIUM_NO_KUBEPROXY ?= "${E2E_DIR}/data/cni/cilium/cilium-no-kubeproxy.yaml" # helm template cilium cilium/cilium --version 1.13.0 -n kube-system --set hubble.enabled=false --set cni.chainingMode=portmap  --set sessionAffinity=true --set kubeProxyReplacement=strict | sed 's/${BIN_PATH}/$BIN_PATH/g'

# CRD_OPTIONS define options to add to the CONTROLLER_GEN
CRD_OPTIONS ?= "crd:crdVersions=v1"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Get latest git hash
GIT_COMMIT_HASH=$(shell git rev-parse HEAD)

# Get the local image registry required for clusterctl upgrade tests
LOCAL_IMAGE_REGISTRY ?= localhost:5000

ifeq (${MAKECMDGOALS},test-e2e-clusterctl-upgrade)
	IMG_TAG=e2e-${GIT_COMMIT_HASH}
	IMG_REPO=${LOCAL_IMAGE_REGISTRY}/controller
endif

ifeq (${MAKECMDGOALS},docker-build-e2e)
	IMG_TAG=e2e-${GIT_COMMIT_HASH}
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

RUN_VALIDATION_TESTS_ONLY?=false # for CI please set EXPORT_RESULT to true
LABEL_FILTERS ?=
ifeq ($(RUN_VALIDATION_TESTS_ONLY), true)
		LABEL_FILTER_ARGS = only-for-validation
else
		LABEL_FILTER_ARGS = !only-for-validation
endif
ifneq ($(LABEL_FILTERS),)
		LABEL_FILTER_ARGS := "$(LABEL_FILTER_ARGS) && $(LABEL_FILTERS)"
endif
JUNIT_REPORT_FILE ?= "junit.e2e_suite.1.xml"
GINKGO_SKIP ?= "clusterctl-Upgrade"
GINKGO_FOCUS ?= ""
GINKGO_NODES  ?= 1
E2E_CONF_FILE  ?= ${E2E_DIR}/config/nutanix.yaml
ARTIFACTS ?= ${REPO_ROOT}/_artifacts
SKIP_RESOURCE_CLEANUP ?= false
USE_EXISTING_CLUSTER ?= false
GINKGO_NOCOLOR ?= false
FLAVOR ?= e2e

# set ginkgo focus flags, if any
ifneq ($(strip $(GINKGO_FOCUS)),)
_FOCUS_ARGS := $(foreach arg,$(strip $(GINKGO_FOCUS)),--focus="$(arg)")
endif

# to set multiple ginkgo skip flags, if any
ifneq ($(strip $(GINKGO_SKIP)),)
_SKIP_ARGS := $(foreach arg,$(strip $(GINKGO_SKIP)),--skip="$(arg)")
endif
.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


##@ Development

.PHONY: manifests
manifests: ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	controller-gen $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: release-manifests
release-manifests: manifests cluster-templates
	mkdir -p $(RELEASE_DIR)
	kustomize build config/default > $(RELEASE_DIR)/infrastructure-components.yaml
	cp $(TEMPLATES_DIR)/cluster-template*.yaml $(RELEASE_DIR)
	cp $(REPO_ROOT)/metadata.yaml $(RELEASE_DIR)/metadata.yaml

.PHONY: generate
generate: ## Generate code containing DeepCopy, DeepCopyInto, DeepCopyObject method implementations and API conversion implementations.
	controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
	conversion-gen \
	--input-dirs=./api/v1alpha4 \
	--input-dirs=./api/v1beta1 \
	--build-tag=ignore_autogenerated_core \
	--output-file-base=zz_generated.conversion \
	--go-header-file=./hack/boilerplate.go.txt

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

kind-create: ## Create a kind cluster and deploy the latest supported cluster API version
	kind create cluster --name=${KIND_CLUSTER_NAME}

kind-delete: ## Delete the kind cluster
	kind delete cluster --name=${KIND_CLUSTER_NAME}

##@ Build

.PHONY: build
build: mocks generate fmt ## Build manager binary.
	echo "Git commit hash: ${GIT_COMMIT_HASH}"
	go build -ldflags "-X main.gitCommitHash=${GIT_COMMIT_HASH}" -o bin/manager main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

.PHONY: docker-build
docker-build:  ## Build docker image with the manager.
	echo "Git commit hash: ${GIT_COMMIT_HASH}"
	KO_DOCKER_REPO=ko.local GOFLAGS="-ldflags=-X=main.gitCommitHash=${GIT_COMMIT_HASH}" ko build -B --platform=${PLATFORMS} -t ${IMG_TAG} -L .

.PHONY: docker-push
docker-push:  ## Push docker image with the manager.
	KO_DOCKER_REPO=${IMG_REPO} ko build --bare --platform=${PLATFORMS} -t ${IMG_TAG} .

.PHONY: docker-push-kind
docker-push-kind:  ## Make docker image available to kind cluster.
	GOOS=linux GOARCH=${shell go env GOARCH} KO_DOCKER_REPO=ko.local ko build -B -t ${IMG_TAG} -L .
	docker tag ko.local/cluster-api-provider-nutanix:${IMG_TAG} ${IMG}
	kind load docker-image --name ${KIND_CLUSTER_NAME} ${IMG}

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif


.PHONY: install
install: manifests ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	kustomize build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	kustomize build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests docker-push-kind ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	clusterctl delete --infrastructure nutanix:${LOCAL_PROVIDER_VERSION} --include-crd || true
	clusterctl init --infrastructure nutanix:${LOCAL_PROVIDER_VERSION} -v 9
	# cd config/manager && kustomize edit set image controller=${IMG}
	# kustomize build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	kustomize build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Templates

.PHONY: cluster-e2e-templates
cluster-e2e-templates: cluster-e2e-templates-v1beta1 cluster-e2e-templates-v1alpha4 cluster-e2e-templates-v124 cluster-e2e-templates-v130 ## Generate cluster templates for all versions

cluster-e2e-templates-v124: ## Generate cluster templates for CAPX v1.2.4
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1.2.4/cluster-template --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1.2.4/cluster-template.yaml

cluster-e2e-templates-v130: ## Generate cluster templates for CAPX v1.3.0
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1.3.0/cluster-template --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1.3.0/cluster-template.yaml

cluster-e2e-templates-v1alpha4:  ## Generate cluster templates for v1alpha4
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1alpha4/cluster-template --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1alpha4/cluster-template.yaml

cluster-e2e-templates-v1beta1: ## Generate cluster templates for v1beta1
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-secret --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-secret.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-nutanix-cluster --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-nutanix-cluster.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-additional-categories --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-additional-categories.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-nmt --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-nmt.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-project --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-project.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-upgrades --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-upgrades.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-md-remediation --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-md-remediation.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-kcp-remediation --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-kcp-remediation.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-kcp-scale-in --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-kcp-scale-in.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-csi --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-csi.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-failure-domains --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-failure-domains.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-clusterclass --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-clusterclass.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-clusterclass --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/clusterclass-e2e.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-topology --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-topology.yaml

cluster-e2e-templates-no-kubeproxy: ##Generate cluster templates without kubeproxy
	# v1alpha4
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1alpha4/no-kubeproxy/cluster-template --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1alpha4/cluster-template.yaml

	# v1beta1
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-no-secret --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-secret.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-no-nutanix-cluster --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-nutanix-cluster.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-additional-categories --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-additional-categories.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-no-nmt --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-no-nmt.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-project --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-project.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-upgrades --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-upgrades.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-md-remediation --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-md-remediation.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-kcp-remediation --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-kcp-remediation.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-kcp-scale-in --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-kcp-scale-in.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-csi --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-csi.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-failure-domains --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-failure-domains.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-clusterclass --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-clusterclass.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-clusterclass --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/clusterclass-e2e.yaml
	kustomize build $(NUTANIX_E2E_TEMPLATES)/v1beta1/no-kubeproxy/cluster-template-topology --load-restrictor LoadRestrictionsNone > $(NUTANIX_E2E_TEMPLATES)/v1beta1/cluster-template-topology.yaml

cluster-templates: ## Generate cluster templates for all flavors
	kustomize build $(TEMPLATES_DIR)/base > $(TEMPLATES_DIR)/cluster-template.yaml
	kustomize build $(TEMPLATES_DIR)/csi > $(TEMPLATES_DIR)/cluster-template-csi.yaml
	kustomize build $(TEMPLATES_DIR)/clusterclass > $(TEMPLATES_DIR)/cluster-template-clusterclass.yaml
	kustomize build $(TEMPLATES_DIR)/topology > $(TEMPLATES_DIR)/cluster-template-topology.yaml

##@ Testing

.PHONY: docker-build-e2e
docker-build-e2e: ## Build docker image with the manager with e2e tag.
	echo "Git commit hash: ${GIT_COMMIT_HASH}"
	KO_DOCKER_REPO=ko.local GOFLAGS="-ldflags=-X=main.gitCommitHash=${GIT_COMMIT_HASH}" ko build -B --platform=${PLATFORMS_E2E} -t ${IMG_TAG} -L .
	docker tag ko.local/cluster-api-provider-nutanix:${IMG_TAG} ${IMG_REPO}:e2e

.PHONY: prepare-local-clusterctl
prepare-local-clusterctl: manifests cluster-templates  ## Prepare overide file for local clusterctl.
	mkdir -p ~/.cluster-api/overrides/infrastructure-nutanix/${LOCAL_PROVIDER_VERSION}
	cd config/manager && kustomize edit set image controller=${IMG}
	kustomize build config/default > ~/.cluster-api/overrides/infrastructure-nutanix/${LOCAL_PROVIDER_VERSION}/infrastructure-components.yaml
	cp ./metadata.yaml ~/.cluster-api/overrides/infrastructure-nutanix/${LOCAL_PROVIDER_VERSION}/
	cp ./templates/cluster-template*.yaml ~/.cluster-api/overrides/infrastructure-nutanix/${LOCAL_PROVIDER_VERSION}/
	env LOCAL_PROVIDER_VERSION=$(LOCAL_PROVIDER_VERSION) \
		envsubst -no-unset -no-empty -no-digit < ./clusterctl.yaml > ~/.cluster-api/clusterctl.yaml

.PHONY: mocks
mocks: ## Generate mocks for the project
	mockgen -destination=mocks/ctlclient/client_mock.go -package=mockctlclient sigs.k8s.io/controller-runtime/pkg/client Client
	mockgen -destination=mocks/ctlclient/manager_mock.go -package=mockctlclient sigs.k8s.io/controller-runtime/pkg/manager Manager
	mockgen -destination=mocks/ctlclient/cache_mock.go -package=mockctlclient sigs.k8s.io/controller-runtime/pkg/cache Cache
	mockgen -destination=mocks/k8sclient/cm_informer.go -package=mockk8sclient k8s.io/client-go/informers/core/v1 ConfigMapInformer
	mockgen -destination=mocks/k8sclient/secret_informer.go -package=mockk8sclient k8s.io/client-go/informers/core/v1 SecretInformer

GOTESTPKGS = $(shell go list ./... | grep -v /mocks)

.PHONY: unit-test
unit-test: mocks  ## Run unit tests.
ifeq ($(EXPORT_RESULT), true)
	$(eval OUTPUT_OPTIONS = | go-junit-report -set-exit-code > junit-report.xml)
endif
	KUBEBUILDER_ASSETS="$(shell setup-envtest use $(ENVTEST_K8S_VERSION)  --arch=amd64 -p path)" $(GOTEST) $(GOTESTPKGS) $(OUTPUT_OPTIONS)

.PHONY: coverage
coverage: mocks ## Run the tests of the project and export the coverage
	KUBEBUILDER_ASSETS="$(shell setup-envtest use $(ENVTEST_K8S_VERSION)  --arch=amd64 -p path)" $(GOTEST) -cover -covermode=count -coverprofile=profile.cov $(GOTESTPKGS)
	$(GOTOOL) cover -func profile.cov
ifeq ($(EXPORT_RESULT), true)
	gocov convert profile.cov | gocov-xml > coverage.xml
endif

.PHONY: ginkgo-help
ginkgo-help:
	ginkgo help run

.PHONY: test-e2e
test-e2e: docker-build-e2e cluster-e2e-templates cluster-templates ## Run the end-to-end tests
	mkdir -p $(ARTIFACTS)
	NUTANIX_LOG_LEVEL=debug ginkgo -v \
		--trace \
		--progress \
		--tags=e2e \
		--label-filter=$(LABEL_FILTER_ARGS) \
		$(_SKIP_ARGS) \
		$(_FOCUS_ARGS) \
		--nodes=$(GINKGO_NODES) \
		--no-color=$(GINKGO_NOCOLOR) \
		--output-dir="$(ARTIFACTS)" \
		--junit-report=${JUNIT_REPORT_FILE} \
		--timeout="24h" \
		--always-emit-ginkgo-writer \
		$(GINKGO_ARGS) ./test/e2e -- \
		-e2e.artifacts-folder="$(ARTIFACTS)" \
		-e2e.config="$(E2E_CONF_FILE)" \
		-e2e.skip-resource-cleanup=$(SKIP_RESOURCE_CLEANUP) \
		-e2e.use-existing-cluster=$(USE_EXISTING_CLUSTER)

.PHONY: test-e2e-no-kubeproxy
test-e2e-no-kubeproxy: docker-build-e2e cluster-e2e-templates-no-kubeproxy cluster-templates ## Run the end-to-end tests without kubeproxy
	mkdir -p $(ARTIFACTS)
	NUTANIX_LOG_LEVEL=debug ginkgo -v \
		--trace \
		--progress \
		--tags=e2e \
		--label-filter=$(LABEL_FILTER_ARGS) \
		$(_SKIP_ARGS) \
		--nodes=$(GINKGO_NODES) \
		--no-color=$(GINKGO_NOCOLOR) \
		--output-dir="$(ARTIFACTS)" \
		--junit-report=${JUNIT_REPORT_FILE} \
		--timeout="24h" \
		--always-emit-ginkgo-writer \
		$(GINKGO_ARGS) ./test/e2e -- \
		-e2e.artifacts-folder="$(ARTIFACTS)" \
		-e2e.config="$(E2E_CONF_FILE)" \
		-e2e.skip-resource-cleanup=$(SKIP_RESOURCE_CLEANUP) \
		-e2e.use-existing-cluster=$(USE_EXISTING_CLUSTER)

.PHONY: list-e2e
list-e2e: docker-build-e2e cluster-e2e-templates cluster-templates ## Run the end-to-end tests
	mkdir -p $(ARTIFACTS)
	ginkgo -v --trace --dry-run --tags=e2e --label-filter="$(LABEL_FILTERS)" $(_SKIP_ARGS) --nodes=$(GINKGO_NODES) \
	    --no-color=$(GINKGO_NOCOLOR) --output-dir="$(ARTIFACTS)" \
	    $(GINKGO_ARGS) ./test/e2e -- \
	    -e2e.artifacts-folder="$(ARTIFACTS)" \
	    -e2e.config="$(E2E_CONF_FILE)" \
	    -e2e.skip-resource-cleanup=$(SKIP_RESOURCE_CLEANUP) -e2e.use-existing-cluster=$(USE_EXISTING_CLUSTER)

.PHONY: test-e2e-calico
test-e2e-calico:
	CNI=$(CNI_PATH_CALICO) $(MAKE) test-e2e

.PHONY: test-e2e-flannel
test-e2e-flannel:
	CNI=$(CNI_PATH_FLANNEL) $(MAKE) test-e2e

.PHONY: test-e2e-cilium
test-e2e-cilium:
	CNI=$(CNI_PATH_CILIUM) $(MAKE) test-e2e

.PHONY: test-e2e-cilium-no-kubeproxy
test-e2e-cilium-no-kubeproxy:
	CNI=$(CNI_PATH_CILIUM_NO_KUBEPROXY) $(MAKE) test-e2e-no-kubeproxy

.PHONY: test-e2e-all-cni
test-e2e-all-cni: test-e2e test-e2e-calico test-e2e-flannel test-e2e-cilium test-e2e-cilium-no-kubeproxy

.PHONY: test-e2e-clusterctl-upgrade
test-e2e-clusterctl-upgrade: docker-build-e2e cluster-e2e-templates cluster-templates ## Run the end-to-end tests
	echo "Image tag for E2E test is ${IMG_TAG}"
	docker tag ko.local/cluster-api-provider-nutanix:${IMG_TAG} ${IMG_REPO}:${IMG_TAG}
	docker push ${IMG_REPO}:${IMG_TAG}
	GINKGO_SKIP="" GIT_COMMIT="${GIT_COMMIT_HASH}" $(MAKE) test-e2e-calico

##@ Lint and Verify

.PHONY: lint
lint: ## Lint the codebase
	golangci-lint run -v

lint-yaml: ## Use yamllint on the yaml file of your projects
ifeq ($(EXPORT_RESULT), true)
	$(eval OUTPUT_OPTIONS = | yamllint-checkstyle > yamllint-checkstyle.xml)
endif
	yamllint -c .yamllint --no-warnings -f parsable $(shell git ls-files '*.yml' '*.yaml') $(OUTPUT_OPTIONS)

.PHONY: lint-fix
lint-fix: ## Lint the codebase and run auto-fixers if supported by the linter
	GOLANGCI_LINT_EXTRA_ARGS="$(GOLANGCI_LINT_EXTRA_ARGS) --fix" $(MAKE) lint

# Make any new verify task a dependency of this target
.PHONY: verify ## Run all verify targets
verify: verify-manifests

# Adapted from https://github.com/kubernetes-sigs/cluster-api/blob/f15e8769a2135429911ce6d8f7124b853c0444a1/Makefile#L651-L656
.PHONY: verify-manifests
verify-manifests: manifests  ## Verify generated manifests are up to date
	@if !(git diff --quiet HEAD); then \
		git diff; \
		echo "generated manifests are out of date in the repository, run make manifests, and commit"; exit 1; \
	fi

## --------------------------------------
## Clean
## --------------------------------------

##@ Clean
.PHONY: clean
clean: ## Clean the build and test artifacts
	rm -rf $(ARTIFACTS) $(BIN_DIR)

## --------------------------------------
## Developer local tests
## --------------------------------------

##@ Test Dev Cluster with and without topology
include test-cluster-without-topology.mk
include test-cluster-with-topology.mk
