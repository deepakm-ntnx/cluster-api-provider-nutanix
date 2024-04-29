//go:build e2e

/*
Copyright 2024 Nutanix

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package e2e

import (
	"context"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

var _ = Describe("When scaling out cluster with topology ", Label("clusterclass"), func() {
	const specName = "cluster-with-topology-scale-out-workflow"
	const flavor = "topology"

	var (
		namespace      *corev1.Namespace
		clusterName    string
		cluster        *clusterv1.Cluster
		cancelWatches  context.CancelFunc
		testHelper     testHelperInterface
		nutanixE2ETest *NutanixE2ETest
	)

	BeforeEach(func() {
		testHelper = newTestHelper(e2eConfig)
		Expect(bootstrapClusterProxy).NotTo(BeNil(), "BootstrapClusterProxy can't be nil")
		namespace, cancelWatches = setupSpecNamespace(ctx, specName, bootstrapClusterProxy, artifactFolder)
		Expect(namespace).NotTo(BeNil())
		nutanixE2ETest = NewNutanixE2ETest(
			WithE2ETestSpecName(specName),
			WithE2ETestHelper(testHelper),
			WithE2ETestConfig(e2eConfig),
			WithE2ETestBootstrapClusterProxy(bootstrapClusterProxy),
			WithE2ETestArtifactFolder(artifactFolder),
			WithE2ETestClusterctlConfigPath(clusterctlConfigPath),
			WithE2ETestClusterTemplateFlavor(flavor),
			WithE2ETestNamespace(namespace),
		)
	})

	AfterEach(func() {
		dumpSpecResourcesAndCleanup(ctx, specName, bootstrapClusterProxy, artifactFolder, namespace, cancelWatches, cluster, e2eConfig.GetIntervals, skipCleanup)
	})

	scaleOutWorkflow := func(targetKubeVer, targetImageName string, fromCPNodeCount, fromWorkerNodeCount, toCPNodeCount, toWorkerNodeCount int) {
		By("Creating a workload cluster with topology")
		clusterTopologyConfig := NewClusterTopologyConfig(
			WithName(clusterName),
			WithKubernetesVersion(targetKubeVer),
			WithControlPlaneCount(fromCPNodeCount),
			WithWorkerNodeCount(fromWorkerNodeCount),
			WithControlPlaneMachineTemplateImage(targetImageName),
			WithWorkerMachineTemplateImage(targetImageName),
		)

		clusterResources, err := nutanixE2ETest.CreateCluster(ctx, clusterTopologyConfig)
		Expect(err).ToNot(HaveOccurred())

		// Set test specific variable so that cluster can be cleaned up after each test
		cluster = clusterResources.Cluster

		By("Waiting until nodes are ready")
		nutanixE2ETest.WaitForNodesReady(ctx, targetKubeVer, clusterResources)

		clusterTopologyConfig = NewClusterTopologyConfig(
			WithName(clusterName),
			WithKubernetesVersion(targetKubeVer),
			WithControlPlaneCount(toCPNodeCount),
			WithWorkerNodeCount(toWorkerNodeCount),
			WithControlPlaneMachineTemplateImage(targetImageName),
			WithWorkerMachineTemplateImage(targetImageName),
		)

		clusterResources, err = nutanixE2ETest.UpgradeCluster(ctx, clusterTopologyConfig)
		Expect(err).ToNot(HaveOccurred())

		By("Waiting for control-plane machines to have the upgraded Kubernetes version")
		nutanixE2ETest.WaitForControlPlaneMachinesToBeUpgraded(ctx, clusterTopologyConfig, clusterResources)

		By("Waiting for machine deployment machines to have the upgraded Kubernetes version")
		nutanixE2ETest.WaitForMachineDeploymentMachinesToBeUpgraded(ctx, clusterTopologyConfig, clusterResources)

		By("Waiting until nodes are ready")
		nutanixE2ETest.WaitForNodesReady(ctx, targetKubeVer, clusterResources)

		By("PASSED!")
	}

	It("Scale out a cluster with topology from 1 CP node to 3 CP nodes with Kube127", Label("Kube127", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube127 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_27")
		kube127Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_27")
		scaleOutWorkflow(kube127, kube127Image, 1, 1, 3, 1)
	})

	It("Scale out a cluster with topology from 1 Worker node to 3 Worker nodes with Kube127", Label("Kube127", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube127 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_27")
		kube127Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_27")
		scaleOutWorkflow(kube127, kube127Image, 1, 1, 1, 3)
	})

	It("Scale out a cluster with topology from 1 CP and Worker node to 3 CP and Worker nodes with Kube127", Label("Kube127", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube127 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_27")
		kube127Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_27")
		scaleOutWorkflow(kube127, kube127Image, 1, 1, 3, 3)
	})

	It("Scale out a cluster with topology from 1 CP node to 3 CP nodes with Kube128", Label("Kube128", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube128 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_28")
		kube128Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_28")
		scaleOutWorkflow(kube128, kube128Image, 1, 1, 3, 1)
	})

	It("Scale out a cluster with topology from 1 Worker node to 3 Worker nodes with Kube128", Label("Kube128", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube128 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_28")
		kube128Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_28")
		scaleOutWorkflow(kube128, kube128Image, 1, 1, 1, 3)
	})

	It("Scale out a cluster with topology from 1 CP and Worker node to 3 CP and Worker nodes with Kube128", Label("Kube128", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube128 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_28")
		kube128Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_28")
		scaleOutWorkflow(kube128, kube128Image, 1, 1, 3, 3)
	})

	It("Scale out a cluster with topology from 1 CP node to 3 CP nodes with Kube129", Label("Kube129", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube129 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_29")
		kube129Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_29")
		scaleOutWorkflow(kube129, kube129Image, 1, 1, 3, 1)
	})

	It("Scale out a cluster with topology from 1 Worker node to 3 Worker nodes with Kube129", Label("Kube129", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube129 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_29")
		kube129Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_29")
		scaleOutWorkflow(kube129, kube129Image, 1, 1, 1, 3)
	})

	It("Scale out a cluster with topology from 1 CP and Worker node to 3 CP and Worker nodes with Kube129", Label("Kube129", "cluster-topology-scale-out"), func() {
		clusterName = testHelper.generateTestClusterName(specName)
		Expect(clusterName).NotTo(BeNil())

		kube129 := testHelper.getVariableFromE2eConfig("KUBERNETES_VERSION_v1_29")
		kube129Image := testHelper.getVariableFromE2eConfig("NUTANIX_MACHINE_TEMPLATE_IMAGE_NAME_v1_29")
		scaleOutWorkflow(kube129, kube129Image, 1, 1, 3, 3)
	})
})
