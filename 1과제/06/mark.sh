# ========================
# 환경변수
# ========================
export DistributionID="<CloudFront_Distribution_ID>"
export BUCKET="gj2026-static-<비번호>"


rm -rf ~/.aws
mkdir -p ~/.aws
export CF_DOMAIN=$(aws cloudfront get-distribution --id ${DistributionID} --query "Distribution.DomainName" --output text)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws configure set default.region ap-northeast-2
aws eks update-kubeconfig --name gj2026-eks-cluster >/dev/null 2>&1
aws ecr get-login-password --region ap-northeast-2 2>/dev/null | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com >/dev/null 2>&1
export InvalidationID=$(aws cloudfront create-invalidation --distribution-id ${DistributionID} --paths "/*" --query "Invalidation.Id" --output text)
aws cloudfront wait invalidation-completed --distribution-id ${DistributionID} --id ${InvalidationID}





aws ec2 describe-vpcs --filter Name=tag:Name,Values=gj2026-vpc --query Vpcs[0].CidrBlock
aws ec2 describe-subnets --filters Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=gj2026-vpc --query 'Vpcs[0].VpcId' --output text) --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,AvailabilityZone]'   --output text | sort
# "10.0.0.0/16"
# gj2026-private-subnet-a 10.0.10.0/24    ap-northeast-2a
# gj2026-private-subnet-b 10.0.11.0/24    ap-northeast-2b


aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=gj2026-private-subnet-a,gj2026-private-subnet-b --query 'Subnets[].SubnetId' --output text | xargs | sed 's/ /,/g')" --query 'sort_by(RouteTables,&Tags[?Key==`Name`]|[0].Value)[].{RT:Tags[?Key==`Name`]|[0].Value,Routes:Routes[].DestinationCidrBlock}' --output text
# gj2026-private-rtb-a
# ROUTES  10.0.0.0/16
# gj2026-private-rtb-b
# ROUTES  10.0.0.0/16


aws ec2 describe-nat-gateways --query 'length(NatGateways)'
aws ec2 describe-internet-gateways --query 'InternetGateways[].Tags[?Key==`Name`].Value[]' --output text
# 0
# gj2026-igw


aws ecr describe-repositories --repository-names "book" --query 'repositories[0].repositoryName' --output text
# book


book_size_bytes=$(aws ecr describe-images --repository-name "book" --query 'imageDetails[?imageTags[0]==`latest`].imageSizeInBytes' --output text)
book_size_mb=$(awk "BEGIN {printf \"%.2f\", $book_size_bytes / 1024 / 1024}")
echo "${book_size_mb}mb"
# 3MB 이하인지 확인


aws dynamodb describe-table --table-name books --query "{TablePK:Table.KeySchema[0].AttributeName,GSI:Table.GlobalSecondaryIndexes[*].{IndexName:IndexName,PK:KeySchema[0].AttributeName}}" --output text
# booking_id
# GSI     client_id-index client_id


aws kms list-aliases --query "Aliases[?TargetKeyId=='$(aws dynamodb describe-table --table-name books --query 'Table.SSEDescription.KMSMasterKeyArn' --output text | awk -F'/' '{print $2}')'].AliasName" --output text
# alias/gj2026-db-key


aws dynamodb put-item --table-name books --item '{"booking_id":{"S":"score-test-001"},"client_id":{"S":"D002"},"username":{"S":"David"},"email":{"S":"lim@example.com"},"concert_name":{"S":"Busan2025"}}' --region ap-northeast-2
# aws: [ERROR]: An error occurred (AccessDeniedException) when calling the PutItem operation: (이하 생략)


aws eks describe-cluster --name gj2026-eks-cluster --query "cluster.[name,version,status,resourcesVpcConfig.endpointPublicAccess,resourcesVpcConfig.endpointPrivateAccess]" --output text && aws kms list-aliases --query "Aliases[?TargetKeyId=='$(aws eks describe-cluster --name gj2026-eks-cluster --query 'cluster.encryptionConfig[0].provider.keyArn' --output text | cut -d/ -f2)'].AliasName" --output text
# gj2026-eks-cluster 1.35 ACTIVE True True
# alias/gj2026-eks-key


for ng in $(aws eks list-nodegroups --cluster-name gj2026-eks-cluster --query 'nodegroups[*]' --output text); do aws eks describe-nodegroup --cluster-name gj2026-eks-cluster --nodegroup-name $ng --query "nodegroup.[nodegroupName,amiType,instanceTypes[0],scalingConfig.desiredSize]" --output text; done
# gj2026-eks-addon-nodegroup    BOTTLEROCKET_x86_64   t3.medium    2
# gj2026-eks-app-nodegroup      BOTTLEROCKET_x86_64   m5.large      2


kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers | while read n; do id=$(echo $n | cut -d. -f2);   aws ec2 describe-instances --instance-ids $id --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text | grep -q $id && echo $n; done
# gj2026.<instance-id>.addon.node
# gj2026.<instance-id>.addon.node
# gj2026.<instance-id>.app.node
# gj2026.<instance-id>.app.node


kubectl get deployment -n skills book
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# book   2/2     2            2           21h


kubectl delete pod -n skills nginx-test >/dev/null 2>&1
docker pull ${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/nginx/nginx:latest >/dev/null 2>&1 && kubectl run nginx-test -n skills --image=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/ecr-public/nginx/nginx:latest --restart=Never 2>/dev/null && sleep 3 && kubectl exec -n skills nginx-test -- curl -m 5 -sS http://book-svc:8080/health 2>&1 | grep -v '^Defaulted container'
# pod/nginx-test created
# curl: (28) Connection timed out after 5002 milliseconds
# command terminated with exit code 28


aws elbv2 describe-load-balancers --names gj2026-alb \
 --query 'LoadBalancers[0].Scheme' --output text && \
aws ec2 describe-tags \
 --filters "Name=resource-id,Values=$(aws elbv2 describe-load-balancers --names gj2026-alb --query 'LoadBalancers[0].VpcId' --output text)" \
 --query "Tags[?Key=='Name'].Value | [0]" --output text
# internal
# gj2026-vpc


aws s3api list-objects-v2 --bucket $BUCKET --query 'Contents[?contains(Key, `/`)==`false`].Key' --output text
# index.html      main.jpeg


aws kms list-aliases --query "Aliases[?TargetKeyId=='$(aws s3api get-bucket-encryption --bucket $BUCKET --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID' --output text | awk -F'/' '{print $NF}')'].AliasName" --output text
# alias/gj2026-s3-key


aws lambda get-function --function-name gj2026-book-reservation --query 'Configuration.[FunctionName,Runtime,State]' --output text
# gj2026-book-reservation python3.14 Active


curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" https://${CF_DOMAIN}
curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" https://${CF_DOMAIN}/main.jpeg
curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" https://${CF_DOMAIN}/index.html
# 200 Miss from cloudfront
# 200 Miss from cloudfront
# 200 Hit from cloudfront


curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"client_id": "C001", "username": "Alice", "email": "kim@example.com", "concert_name": "Busan2025"}' \
     https://${CF_DOMAIN}/v1/book
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"client_id": "C002", "username": "Bob", "email": "han@example.com", "concert_name": "Seoul2025"}' \
     https://${CF_DOMAIN}/v1/book
# {"booking_id":"K16MBR45"}
# {"booking_id":"OCYGWYIO"}


date
curl https://${CF_DOMAIN}/reservation
# 10-2 채점을 위해 실행 시간을 기록합니다.
# [{"username": "Bob", "email": "han@example.com", "concert_name": "Seoul2025"}, {"username": "Alice", "email": "kim@example.com", "concert_name": "Busan2025"}]


curl https://${CF_DOMAIN}/reservation?client_id=C001
# [{"username": "Alice", "email": "kim@example.com", "concert_name": "Busan2025"}]


curl -s -w " %{http_code}" https://${CF_DOMAIN}/v1/book
# Method Not Allowed 405


curl -s -w " %{http_code}" "https://${CF_DOMAIN}/reservation?client_id=123abc"; 
curl -s -w " %{http_code}" "https://${CF_DOMAIN}/reservation?client_id=C@001"; 
curl -s -w " %{http_code}" "https://${CF_DOMAIN}/reservation?client_id=홍길동"; 
# Access Denied 403
# Access Denied 403
# Access Denied 403


aws logs delete-log-group --log-group-name /eks/book-svc/access 2>/dev/null
kubectl -n logging rollout restart ds/aws-for-fluent-bit >/dev/null 2>&1
for i in {1..10}; do curl -sX POST https://$CF_DOMAIN/v1/book > /dev/null; sleep 1; done
sleep 3
for s in $(aws logs describe-log-streams --log-group-name /eks/book-svc/access --query 'logStreams[].logStreamName' --output text); do
  echo "(stream: $s ip: $(aws logs get-log-events --log-group-name /eks/book-svc/access --log-stream-name "$s" --limit 1 --query 'events[0].message' --output text | jq -r '.remote_addr|split(":")[0]'))"
done
# (stream: /book-svc/ap-northeast-2a ip: 10.0.10.66)
# (stream: /book-svc/ap-northeast-2b ip: 10.0.11.234)


echo "${CF_DOMAIN}"/grafana
echo "수동채점"
# Username: admin
# Password: Skills53#
# 로그인 완료 후 위와 같이 WSI Dashboard에 각각 1개씩 찍혔는지 확인되어야합니다. (8-3 명령어 실행 시간과 일치하는지 확인) (최대 3분 대기)