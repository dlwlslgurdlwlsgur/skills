# #################################################
# 채점시 CloudShell에서 wskorea26-vpc-environment-sg 보안그룹을 사용합니다. 구성 후
# 통신에 문제가 없도록 Ingress, Egress를 구성합니다. 특히 EKS 접근에 문제가 없도록 네트워
# 크 구성과 권한 구성을 확인합니다.
# #################################################


ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "ACCOUNT ID: $ACCOUNT_ID"
aws configure set region ap-northeast-2
aws eks update-kubeconfig --region ap-northeast-2 --name wskorea26-cluster 2>/dev/null
CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='wskorea26-concert-cf'].Id | [0]" --output text)
CF_DOMAIN=$(aws cloudfront get-distribution --id $CF_ID --query "Distribution.DomainName" --output text)
BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'wskorea26-concert-bucket-')].Name | [0]" --output text)
ALB_ARN=$(aws elbv2 describe-load-balancers --names wskorea26-book-alb --query "LoadBalancers[0].LoadBalancerArn" --output text)
ALB_DNS=$(aws elbv2 describe-load-balancers --names wskorea26-book-alb --query "LoadBalancers[0].DNSName" --output text)
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query "Listeners[0].ListenerArn" --output text)


aws ec2 describe-vpcs --filter Name=tag:Name,Values=wskorea26-vpc --query "Vpcs[0].CidrBlock" --output text && aws ec2 describe-subnets --filters "Name=tag:Name,Values=wskorea26-pub-subnet-c,wskorea26-pub-subnet-d,wskorea26-priv-subnet-c,wskorea26-priv-subnet-d" --query "sort_by(Subnets,&Tags[?Key=='Name']|[0].Value)[].[Tags[?Key=='Name']|[0].Value,CidrBlock]" --output text
# 172.16.0.0/16
# wskorea26-priv-subnet-c 172.16.201.0/24
# wskorea26-priv-subnet-d 172.16.202.0/24
# wskorea26-pub-subnet-c  172.16.1.0/24
# wskorea26-pub-subnet-d  172.16.2.0/24


for subnet in wskorea26-pub-subnet-c wskorea26-pub-subnet-d; do aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$subnet" --query "Subnets[0].SubnetId" --output text)" --query "RouteTables[0].Tags[?Key=='Name']|[0].Value" --output text; done | sort; for subnet in wskorea26-priv-subnet-c wskorea26-priv-subnet-d; do aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$subnet" --query "Subnets[0].SubnetId" --output text)" --query "RouteTables[0].Tags[?Key=='Name']|[0].Value" --output text; done | sort; aws ec2 describe-route-tables --filters "Name=tag:Name,Values=wskorea26-public-rtb" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text; for rtb in wskorea26-private-rtb-c wskorea26-private-rtb-d; do aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$rtb" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId | [0]" --output text; done
# wskorea26-public-rtb
# wskorea26-public-rtb
# wskorea26-private-rtb-c
# wskorea26-private-rtb-d
# igw-0622e48b2c50767bb
# nat-040f54735f243b349
# nat-0f7673dc390a3b84c


echo $BUCKET && aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "web/main/" --query "sort(Contents[].Key)" --output text
# wskorea26-concert-bucket-103
# web/main/index.html     web/main/main.jpeg


for key in web/main/index.html web/main/main.jpeg; do kms_arn=$(aws s3api head-object --bucket "$BUCKET" --key "$key" --query "SSEKMSKeyId" --output text); key_id=$(echo "$kms_arn" | awk -F'/' '{print $NF}'); aws kms list-aliases --query "Aliases[?TargetKeyId=='$key_id'].AliasName | [0]" --output text; done; aws s3api get-public-access-block --bucket "$BUCKET" --query "PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]" --output text; aws s3api get-bucket-policy-status --bucket "$BUCKET" --query "PolicyStatus.IsPublic" --output text
# alias/wskorea26-s3-key
# alias/wskorea26-s3-key
# True    True    True    True
# False


aws ecr describe-repositories --query "repositories[?repositoryName=='wskorea26-book-repo'].[repositoryName,imageScanningConfiguration.scanOnPush,encryptionConfiguration.encryptionType]" --output text; aws ecr describe-images --repository-name wskorea26-book-repo --image-ids imageTag=stable --query "imageDetails[0].imageTags" --output text; aws ecr describe-image-scan-findings --repository-name wskorea26-book-repo --image-id imageTag=stable --query "imageScanFindings.findingSeverityCounts" --output json
# wskorea26-book-repo     True    KMS
# stable
# {
#     "LOW": 1
# }
# Critical 및 High 취약점이 존재하지 않을 경우 정답


aws dynamodb describe-table --table-name wskorea26-data-table --query "Table.[TableName,KeySchema[0].[AttributeName,KeyType],DeletionProtectionEnabled]" --output text; aws kms list-aliases --query "Aliases[?TargetKeyId=='$(aws dynamodb describe-table --table-name wskorea26-data-table --query "Table.SSEDescription.KMSMasterKeyArn" --output text | awk -F'/' '{print $NF}')'].AliasName | [0]" --output text
# wskorea26-data-table       True
# client_id       HASH       
# alias/wskorea26-dynamodb-key


aws eks describe-cluster --name wskorea26-cluster --query "cluster.[name,version]" --output text; aws eks describe-cluster --name wskorea26-cluster --query "sort(cluster.logging.clusterLogging[?enabled==\`true\`].types[])" --output text
# wskorea26-cluster       1.35
# api     audit   authenticator   controllerManager       scheduler



aws kms list-aliases --query "Aliases[?TargetKeyId=='$(aws eks describe-cluster --name wskorea26-cluster --query "cluster.encryptionConfig[0].provider.keyArn" --output text | awk -F'/' '{print $NF}')'].AliasName | [0]" --output text; aws ec2 describe-subnets --subnet-ids $(aws eks describe-cluster --name wskorea26-cluster --query "cluster.resourcesVpcConfig.subnetIds[]" --output text) --query "sort(Subnets[*].Tags[?Key=='Name'].Value[])" --output text
# alias/wskorea26-eks-key
# wskorea26-priv-subnet-c wskorea26-priv-subnet-d


for ng in wskorea26-addon-ng wskorea26-app-ng; do aws eks describe-nodegroup --cluster-name wskorea26-cluster --nodegroup-name $ng --query "nodegroup.[nodegroupName,instanceTypes[0],tags.Name]" --output text; done; for ng in wskorea26-addon-ng wskorea26-app-ng; do aws ec2 describe-subnets --subnet-ids $(aws eks describe-nodegroup --cluster-name wskorea26-cluster --nodegroup-name $ng --query "nodegroup.subnets[]" --output text) --query "sort(Subnets[*].Tags[?Key=='Name'].Value[])" --output text; done
# wskorea26-addon-ng      t3.medium       wskorea26-addon-node
# wskorea26-app-ng        t3.medium       wskorea26-app-node
# wskorea26-priv-subnet-c wskorea26-priv-subnet-d
# wskorea26-priv-subnet-c wskorea26-priv-subnet-d


kubectl get namespace wskorea26 --output jsonpath='{.metadata.name}' && echo ""; for node in $(kubectl get pod -n kube-system -o wide --no-headers | grep -v "aws-node\|kube-proxy" | awk '{print $7}'); do kubectl get node $node -o jsonpath='{.metadata.labels.node-type}{"\n"}'; done | sort -u; for node in $(kubectl get pod -n wskorea26 -o wide --no-headers | awk '{print $7}'); do kubectl get node $node -o jsonpath='{.metadata.labels.node-type}{"\n"}'; done | sort -u
# wskorea26
# addon
# app


aws lambda get-function-configuration --function-name wskorea26-book-lambda --query "[FunctionName,Runtime,Environment.Variables.TABLE_NAME]" --output text
# wskorea26-book-lambda   python3.14      wskorea26-data-table


aws elbv2 describe-load-balancers --names wskorea26-book-alb --query "LoadBalancers[0].[LoadBalancerName,Scheme]" --output text; aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query "Listeners[0].[Port,Protocol]" --output text
# wskorea26-book-alb      internet-facing
# 80      HTTP


aws elbv2 describe-rules --listener-arn $LISTENER_ARN --query "Rules[*].Conditions[*].HttpHeaderConfig.Values[]" --output text; curl -o /dev/null -s -w "%{http_code}\n" http://$ALB_DNS/book
# wskorea26-cf
# wskorea26-cf
# 403


aws cloudfront get-distribution --id $CF_ID --query "Distribution.[DomainName,Status]" --output text
# dmwmok0pevxlx.cloudfront.net    Deployed


aws cloudfront get-distribution --id $CF_ID --query "Distribution.DistributionConfig.Origins.Items[].[Id,DomainName]" --output text
# wskorea26-alb-origin    wskorea26-book-alb-140244048.ap-northeast-2.elb.amazonaws.com
# wskorea26-s3-origin     wskorea26-concert-bucket-비번호.s3.ap-northeast-2.amazonaws.com


aws cloudfront get-distribution --id $CF_ID --query "Distribution.DistributionConfig.[DefaultCacheBehavior.TargetOriginId,CacheBehaviors.Items[?PathPattern=='/book*'].TargetOriginId|[0],DefaultCacheBehavior.ViewerProtocolPolicy]" --output text
# wskorea26-s3-origin     wskorea26-alb-origin    redirect-to-https


aws cloudfront get-distribution --id $CF_ID --query "Distribution.DistributionConfig.Origins.Items[].CustomHeaders.Items[].[HeaderName,HeaderValue]" --output text
# X-Origin-Verify wskorea26-cf
# wskorea26-s3-access     true


curl -o /dev/null -s -w "%{http_code}\n" https://$CF_DOMAIN; curl -o /dev/null -s -w "%{http_code}\n" http://$CF_DOMAIN/; curl -o /dev/null -s -w "status: %{http_code}, size: %{size_download} bytes\n" https://$CF_DOMAIN/main.jpeg
# 200
# 301
# status: 200, size: 180926 bytes


curl -s -X POST -H 'Content-Type: application/json' -d '{"client_id":"D1114","username":"akaね","email":"akane@ztmy.com","concert_name":"ZUTOMAYO_INTENSE_II"}' https://$CF_DOMAIN/book
# {"booking_id": "77d12a71"}


curl -s -X GET -H 'Content-Type: application/json' "https://$CF_DOMAIN/book?concert_name=ZUTOMAYO_INTENSE_II"
# [{"username": "akaね", "created_at": "2026-06-01T14:53:00.498069+09:00", "email": "akane@ztmy.com", "booking_id": "77d12a71", "client_id": "D1114", "concert_name": "ZUTOMAYO_INTENSE_II"}]


curl -s -o /dev/null -w "%{http_code}\n" -X GET -H 'Content-Type: application/json' "https://$CF_DOMAIN/book"
# 400


# 10 Monitoring Configure (수동)
GRAFANA_ALB_DNS=$(aws elbv2 describe-load-balancers --names wskorea26-grafana-alb --query "LoadBalancers[0].DNSName" --output text)
echo "URL: http://$GRAFANA_ALB_DNS/d/wskorea26/wskorea26-monitoring"
echo "Login: skills-<비번호>-admin / \$korea26!!"

# 1) Grafana에 다음 인증 정보로 로그인을 합니다
# userid: skills-<비번호>-admin | password: \$korea26!!
# 2) 대시보드에 접근이 가능하고, 파드의 CPU, Memory 지표를 확인할 수 있을 경우 정답


# 1) Grafana에 다음 인증 정보로 로그인을 합니다
# userid: skills-<비번호>-admin | password: \$korea26!!
# 2) 대시보드에 접근이 가능하고, 실행 중인 Pod 개수 지표를 확인할 수 있을 경우 정답


# 1) Grafana에 다음 인증 정보로 로그인을 합니다
# userid: skills-<비번호>-admin | password: \$korea26!!
# 2) 대시보드에 접근이 가능하고, 컨테이너 재시작 횟수 지표를 확인할 수 있을 경우 정답


# 1) Grafana에 다음 인증 정보로 로그인을 합니다
# userid: skills-<비번호>-admin | password: \$korea26!!
# 2) 대시보드에 접근이 가능하고, 컨테이너 네트워크 수신량 지표를 확인할 수 있을 경우 정답