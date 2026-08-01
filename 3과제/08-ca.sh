#!/bin/bash
set -x
CLUSTER_NAME="skills-cluster"
REGION="ap-northeast-2"
NODEGROUP_NAME="skills-nodegroup"

ASG_NAME=$(aws eks describe-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name $NODEGROUP_NAME \
  --region $REGION \
  --query "nodegroup.resources.autoScalingGroups[0].name" \
  --output text)

aws autoscaling create-or-update-tags \
  --tags \
    ResourceType=auto-scaling-group,ResourceId="$ASG_NAME",Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
    ResourceType=auto-scaling-group,ResourceId="$ASG_NAME",Key=k8s.io/cluster-autoscaler/$CLUSTER_NAME,Value=owned,PropagateAtLaunch=true

NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --query "nodegroup.nodeRole" --output text)
NODE_ROLE_NAME=$(echo $NODE_ROLE_ARN | awk -F'/' '{print $NF}')

cat <<EOF > cluster-autoscaler-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": ["*"]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name $NODE_ROLE_NAME \
  --policy-name ClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json

rm -f cluster-autoscaler-autodiscover.yaml

curl -s -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

sed -i "s/<YOUR CLUSTER NAME>/${CLUSTER_NAME}/g" cluster-autoscaler-autodiscover.yaml

kubectl apply -f cluster-autoscaler-autodiscover.yaml

rm cluster-autoscaler-autodiscover.yaml cluster-autoscaler-policy.json