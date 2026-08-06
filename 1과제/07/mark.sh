# =======================================
unicorn-mark CloudShell VPC Environment에 접근합니다. 
rm -rf ~/.aws
aws configure를 입력하고 default.region을 ap-northeast-2으로 설정합니다.
export number=<선수등번호>
source kubectl-connect unicorn-eks-cluster
# =======================================


aws ec2 describe-vpcs --filters Name=tag:Name,Values=unicorn-vpc --query "Vpcs[].CidrBlock" --output json | jq -r ".[]"
aws ec2 describe-subnets --filters Name=tag:Name,Values=unicorn-subnet-pub-a,unicorn-subnet-pub-b,unicorn-subnet-pub-c,unicorn-subnet-priv-a,unicorn-subnet-priv-b,unicorn-subnet-priv-c --query "Subnets[].CidrBlock" --output text
# 10.97.0.0/16
# 10.97.10.0/24   10.97.0.0/24    10.97.2.0/24    10.97.12.0/24   10.97.11.0/24   10.97.1.0/24


aws ec2 describe-route-tables --filters "Name=tag:Name,Values=unicorn-rt-*" --query "RouteTables[].[Tags[?Key=='Name']|[0].Value, Routes[?DestinationCidrBlock=='0.0.0.0/0']|[0].GatewayId, Routes[?DestinationCidrBlock=='0.0.0.0/0']|[0].NatGatewayId, length(Associations[?SubnetId!=null])]" --output text
# unicorn-rt-priv-b None	nat-0d7aac9f8d35d2289 1
# unicorn-rt-pub	igw-086901b749303496a None	3
# unicorn-rt-priv-a None	nat-05cab70f28b9ad467 1
# unicorn-rt-priv-c None	nat-0bc21e61017b3eae5 1


VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=unicorn-vpc --query "Vpcs[0].VpcId" --output text)
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID --query "VpcEndpoints[].ServiceName" --output json | jq -r ".[]"
aws ec2 describe-flow-logs --filter Name=resource-id,Values=$VPC_ID --query "length(FlowLogs)" --output text
# com.amazonaws.ap-northeast-2.s3
# com.amazonaws.ap-northeast-2.ecr.api
# com.amazonaws.ap-northeast-2.ecr.dkr
# 1
# * 출력값에 s3, ecr.api, ecr.dkr가 포함되어 있고, 1 이상이면 득점.


for a in app data platform; do
  aws kms get-key-rotation-status --key-id $(aws kms describe-key --key-id alias/unicorn-kms-$a --query "KeyMetadata.KeyId" --output text) --query "[KeyRotationEnabled, RotationPeriodInDays]" --output text
done
# True    90
# True    90
# True    90


ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET=unicorn-web-$ACCOUNT_ID
aws s3api list-buckets --query "Buckets[?contains(Name, 'unicorn-web-')].Name" | jq -r '.[]'
aws s3api get-public-access-block --bucket $BUCKET --query "PublicAccessBlockConfiguration" --output json | jq -r 'to_entries | map(.value) | @tsv'
aws s3api get-bucket-versioning --bucket $BUCKET --query "Status" --output text
aws s3api get-bucket-encryption --bucket $BUCKET --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.[SSEAlgorithm, KMSMasterKeyID]" --output text
# unicorn-web-837933860870
# true    true    true    true
# Enabled
# aws:kms arn:aws:kms:ap-northeast-2:837933860870:key/2ec8a562-b337-4f43


aws dynamodb describe-table --table-name unicorn-concert-db --query "Table.{Billing:BillingModeSummary.BillingMode, PK:KeySchema[?KeyType=='HASH'].AttributeName|[0], GSIName:GlobalSecondaryIndexes[0].IndexName, GSI_PK:GlobalSecondaryIndexes[0].KeySchema[?KeyType=='HASH'].AttributeName|[0], GSI_SK:GlobalSecondaryIndexes[0].KeySchema[?KeyType=='RANGE'].AttributeName|[0], GSIProj:GlobalSecondaryIndexes[0].Projection.ProjectionType, SSEType:SSEDescription.SSEType, SSEKms:SSEDescription.KMSMasterKeyArn, Delete:DeletionProtectionEnabled}" --output json
aws dynamodb describe-continuous-backups --table-name unicorn-concert-db --query "ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus" --output text
# {
#     "Billing": "PAY_PER_REQUEST",
#     "PK": "booking_id",
#     "GSIName": "client-id-created-at-index",
#     "GSI_PK": "client_id",
#     "GSI_SK": "created_at",
#     "GSIProj": "ALL",
#     "SSEType": "KMS",
#     "SSEKms": "arn:aws:kms:ap-northeast-2:계정ID:key/6fe58a37-030",
#     "Delete": true
# }
# ENABLED


aws ecr describe-repositories --repository-names unicorn-concert-app --query "repositories[0].{Scan:imageScanningConfiguration.scanOnPush, Mutability:imageTagMutability, Enc:encryptionConfiguration.encryptionType}" --output json | jq -r ".[]"
aws ecr describe-images --repository-name unicorn-concert-app --query "sort(imageDetails[].imageTags[])" --output json | jq -r '@tsv'
aws ecr describe-image-scan-findings --repository-name unicorn-concert-app --image-id imageTag=v1.0.0 --query "imageScanFindings.findingSeverityCounts" --output json | jq .
# true
# IMMUTABLE_WITH_EXCLUSION
# KMS
# latest  v1.0.0 * 버전이 더 존재하는 것은 무시합니다.
# * 버전 태그 아래 취약점 개수가 출력되지 않아야 합니다.


aws eks describe-cluster --name unicorn-eks-cluster --query "cluster.version" --output text
aws eks describe-cluster --name unicorn-eks-cluster --query "cluster.resourcesVpcConfig.[endpointPublicAccess, endpointPrivateAccess]" --output json | jq -r '@tsv'
aws eks describe-cluster --name unicorn-eks-cluster --query "cluster.logging.clusterLogging[?enabled==\`true\`].types[]" --output json | jq -r '@tsv'
aws eks describe-cluster --name unicorn-eks-cluster --query "cluster.encryptionConfig[].provider.keyArn" --output text
aws eks describe-cluster --name unicorn-eks-cluster --query "cluster.accessConfig.authenticationMode" --output text
# 1.35
# false    true
# api     audit   authenticator   controllerManager       scheduler
# arn:aws:kms:ap-northeast-2:837933860870:key/b54d1980-5bc9-48
# API


kubectl get nodes -l unicorn=app -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}'
kubectl get nodes -l unicorn=addon --no-headers | wc -l
aws ec2 describe-instances --filters Name=tag:Name,Values=unicorn-k8snode-app-node Name=instance-state-name,Values=running --query "length(Reservations[].Instances[])" --output text
aws ec2 describe-instances --filters Name=tag:Name,Values=unicorn-k8snode-addon-node Name=instance-state-name,Values=running --query "length(Reservations[].Instances[])" --output text
aws ec2 describe-instances --filters Name=tag:Name,Values=unicorn-k8snode-app-node Name=instance-state-name,Values=running --query "Reservations[].Instances[].PublicIpAddress" --output json
# ap-northeast-2a <- 해당 부분의 2개 이상 AZ 출력되면 정답
# ap-northeast-2b
# 1 이상
# 2 이상
# 1 이상
# []


kubectl get deploy unicorn-book-app-deploy -n unicorn -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' --no-headers
kubectl get svc unicorn-book-app-svc -n unicorn -o custom-columns='NAME:.metadata.name,TYPE:.spec.type' --no-headers
kubectl get deploy unicorn-book-app-deploy -n unicorn -o jsonpath='liveness={.spec.template.spec.containers[0].livenessProbe.httpGet.path} readiness={.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}graceful={.spec.template.spec.terminationGracePeriodSeconds} preStop={.spec.template.spec.containers[0].lifecycle.preStop}{"\n"}'
kubectl get pods -n unicorn -l app -o jsonpath='{range .items[*]}{.spec.nodeSelector.unicorn}{"\n"}{end}' | sort -u
aws eks list-pod-identity-associations --cluster-name unicorn-eks-cluster --namespace unicorn --query "associations[].serviceAccount" --output text
# unicorn-book-app-deploy   2     2 <- 빨간색 부분 두 값이 같다면 정답
# unicorn-book-app-svc
# liveness=/health readiness=/health
# graceful=45 preStop={"exec":{"command":["/bin/sh","-c","sleep 15"]}}
# app
# unicorn-book-app-sa <- 출력되는 값이 있다면 정답


aws lambda get-function-configuration --function-name unicorn-get-booking-func --query "[FunctionName, KMSKeyArn, LoggingConfig.LogGroup]" --output json | jq -r ".[]"
# unicorn-get-booking-func
# arn:aws:kms:ap-northeast-2:837933860870:key/b54d1980-5bc9-482f
# /unicorn/lambda/get-booking


ALB_ARN=$(aws elbv2 describe-load-balancers --names unicorn-alb --query "LoadBalancers[0].LoadBalancerArn" --output text)
aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query "LoadBalancers[0].[Scheme, Type, State.Code]" --output text
aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query "Listeners[0].[Protocol, Port]" --output text
aws elbv2 describe-target-groups --names unicorn-tg --query "TargetGroups[0].TargetGroupName" --output text
# internal        application     active
# HTTP    80
# unicorn-tg


aws cloudfront get-distribution-config --id $(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].Id | [0]" --output text) --query "DistributionConfig.Origins.Items[].[Id, OriginAccessControlId, VpcOriginConfig.VpcOriginId]" --output text
aws s3api get-bucket-policy --bucket unicorn-web-$(aws sts get-caller-identity --query Account --output text) --query "Policy" --output text | jq -r '.Statement[] | .Principal.Service, .Condition.StringEquals."AWS:SourceArn"'
# s3-origin  E5QU162JYR0HC   None <- Origin 2개 존재할 경우 정답
# app-origin  vo_CYuIQTnExqrDBT6a97EQ6T
# cloudfront.amazonaws.com
# arn:aws:cloudfront::837933860870:distribution/E1FBZ2QNYFHPN1


CF=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].DomainName | [0]" --output text)
RESP=$(curl -s -X POST "https://$CF/v1/book" -H 'Content-Type: application/json' -d '{"client_id":"C-MARK","username":"Judge","email":"judge@skills.kr","concert_name":"UnicornMark2026"}')
echo "$RESP"
BID=$(echo "$RESP" | jq -r '.booking_id')
aws dynamodb get-item --table-name unicorn-concert-db --key "{\"booking_id\":{\"S\":\"$BID\"}}" --query "Item.{booking_id:booking_id.S, client_id:client_id.S, concert_name:concert_name.S, created_at:created_at.S}" --output json
# {"booking_id":"1DBMHYL0"}
# {
#     "booking_id": "1DBMHYL0",
#     "client_id": "C-MARK",
#     "concert_name": "UnicornMark2026",
#     "created_at": "2026-05-31T20:00:59Z"
# }


curl -s "https://$CF/v1/book?booking_id=$BID" | jq .
# {
#   "username": "Judge",
#   "created_at": "2026-05-31T20:00:59Z",
#   "email": "judge@skills.kr",
#   "booking_id": "1DBMHYL0",
#   "client_id": "C-MARK",
#   "concert_name": "UnicornMark2026"
# }
# 8-3-A의 출력값과 같으면 득점


curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 -X POST "http://$(aws elbv2 describe-load-balancers --names unicorn-alb --query "LoadBalancers[0].DNSName" --output text)/v1/book" -H 'Content-Type: application/json' -d '{"client_id":"DIRECT"}' || echo "000"
# 000
# 000 * 또는 403이 출력되었을 경우 득점


curl -s -o /dev/null -w "%{http_code}\n" "https://$CF/?probe=<script>alert(1)</script>"
# 403


aws iam get-role --role-name unicorn-audit-role --output json | jq -r '.Role | [.MaxSessionDuration, .AssumeRolePolicyDocument.Statement[0].Principal.AWS, .AssumeRolePolicyDocument.Statement[0].Condition.StringEquals["sts:ExternalId"]] | map(tostring) | join(" ")'
for p in $(aws iam list-role-policies --role-name unicorn-audit-role --query "PolicyNames[]" --output text); do
  aws iam get-role-policy --role-name unicorn-audit-role --policy-name $p --query "PolicyDocument.Statement[].Action[]" --output text; done
# 3600 arn:aws:iam::111122223333:root unicorn-audit-2026<선수등번호>
# dynamodb:GetItem dynamodb:Query ec2:DescribeVpcs eks:Describe
# 권한 정책의 경우 해당 부분 포함하며, *이 없으면 득점 인정.


ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN=arn:aws:iam::$ACCOUNT_ID:role/unicorn-audit-role
echo "[1] no external-id:"; aws sts assume-role --role-arn $ROLE_ARN --role-session-name mk 2>&1 | grep -oE AccessDenied | head -1
read -r AK SK TK < <(aws sts assume-role --role-arn $ROLE_ARN --role-session-name mk --external-id unicorn-audit-2026$number --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text)
export AWS_ACCESS_KEY_ID=$AK AWS_SECRET_ACCESS_KEY=$SK AWS_SESSION_TOKEN=$TK
echo "[2] assumed:"; aws sts get-caller-identity --query Arn --output text
echo "[3] allowed:"; aws ec2 describe-vpcs --filters Name=tag:Name,Values=unicorn-vpc --query "Vpcs[0].VpcId" --output text
echo "[4] denied:"; aws ec2 describe-instances 2>&1 | grep -oE "AccessDenied|UnauthorizedOperation" | head -1
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
# AccessDenied
# arn:aws:sts::계정ID:assumed-role/unicorn-audit-role/mk
# vpc-08cc0ca87bdb7d71f
# UnauthorizedOperation


curl -s -o /dev/null -w "%{http_code}\n" "https://$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].DomainName | [0]" --output text)/health"
kubectl exec -n unicorn $(kubectl get pods -n unicorn -l app -o jsonpath='{.items[0].metadata.name}') -c book -- printenv AWS_REGION TABLE_NAME
# 200
# ap-northeast-2
# unicorn-concert-db


aws logs get-log-events --log-group-name /unicorn/eks/book-app --log-stream-name "$(aws logs describe-log-streams --log-group-name /unicorn/eks/book-app --order-by LastEventTime --descending --limit 1 --query "logStreams[0].logStreamName" --output text)" --limit 1 --start-from-head --query "events[-1].message" --output text | jq -r 'keys_unsorted | sort | join(",")'
aws logs filter-log-events --log-group-name /unicorn/eks/book-app --filter-pattern '"/health"' --query "events[].message" --output text | grep -c .
# client_ip,method,path,status_code,timestamp
# 0


kubectl get pods -n monitoring -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' --no-headers | grep -iE "prometheus-|grafana"
kubectl get servicemonitor -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -iE "kube-controller-manager|kube-scheduler|kube-etcd" | wc -l
# 강조된 부분이 일치해야 합니다. (Suffix, 개수는 다를 수 있음)
# prometheus-unicorn-monitoring-kube-pr-prometheus-0 Running
# unicorn-monitoring-grafana-7974ccf57f-j585v  Running
# 0


date -u "+%Y-%m-%dT%H:%M:%SZ"
SINCE=$(date +%s)
curl -s -X POST "https://$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].DomainName | [0]" --output text)/v1/book" -H 'Content-Type: application/json' -d '{"client_id":"C-FRESH","username":"Fresh","email":"fresh@skills.kr","concert_name":"FreshMark"}' > /dev/null
echo "waiting 30s for log pipeline" && sleep 30
aws logs filter-log-events --log-group-name /unicorn/eks/book-app --start-time ${SINCE}000 --filter-pattern '{ $.method = "POST" && $.path = "/v1/book" }' --query "events[-1].message" --output text
# 2026-05-31T23:54:40Z
# waiting 30s for log pipeline
# {"timestamp":"2026-05-31T23:54:42Z","method":"POST","path":"/v1/book","status_code":200,"client_ip":"10.97.12.184"}
# * 출력값 형식이 위와 같고, 빨간색 부분의 시간 차가 1분 이내면 득점. 


CF=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].DomainName | [0]" --output text)
sleep 60
for i in $(seq 1 100); do curl -s -o /dev/null "https://$CF/health"; done
sleep 30
curl -s -o /dev/null -w "%{http_code}\n" "https://$CF/health"
curl -s "https://$CF/health"
# 403
# Request blocked by Unicorn WAF


# unicorn-grafana-alb에 접근하여 skills<선수등번호> / HelloKrSkills!<등번호>@로 로그인합니다. unicorn-grafana-dashboard
# 1. EKS Node CPU Usage (%) - Time Series
# 2. EKS Node Memory Usage (%) - Time Series
# 3. unicorn Namespace Pod Status - Stat, graph 포함
# 4. Book App Ready Pods - Stat
# 5. Book App HTTP Request Duration - Time Series