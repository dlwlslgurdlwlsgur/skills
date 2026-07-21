cat <<EOF > cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: skm-eks-cluster
  region: ap-northeast-2
  version: "1.35"
  tags:
    Project: skillsmarket

iam:
  withOIDC: true

managedNodeGroups:
  - name: skm-cluster-addon-ng
    instanceType: t3.medium
    minSize: 1
    desiredCapacity: 1
    maxSize: 1
    privateNetworking: true
    amiFamily: AmazonLinux2023
    tags:
      Name: skm-cluster-addon-ng-node
    taints:
      - key: CriticalAddonsOnly
        value: "true"
        effect: NoSchedule
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
EOF