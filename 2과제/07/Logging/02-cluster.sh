cat <<EOF >> cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: o11y-cluster
  region: ap-northeast-1
  version: "1.35"
availabilityZones:
  - ap-northeast-1a
  - ap-northeast-1c
iam:
  withOIDC: true
managedNodeGroups:
  - name: o11y-ng
    instanceType: t3.medium
    amiFamily: AmazonLinux2023
    minSize: 2
    maxSize: 2
    desiredCapacity: 2
    privateNetworking: true
    preBootstrapCommands:
      - "timedatectl set-timezone Asia/Seoul"
    tags:
      Name: o11y-node
    propagateASGTags: true
addons:
  - name: vpc-cni
  - name: kube-proxy
  - name: coredns
  - name: aws-ebs-csi-driver
    wellKnownPolicies:
      ebsCSIController: true
EOF