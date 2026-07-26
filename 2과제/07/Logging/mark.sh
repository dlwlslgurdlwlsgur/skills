source kubectl-connect o11y-cluster
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
rm -rf ~/.aws
aws sts get-caller-identity | jq .Account


aws eks describe-cluster --name o11y-cluster --query 'cluster.[name, version, status]' --output text --region ap-northeast-1
aws eks describe-nodegroup --cluster-name o11y-cluster --nodegroup-name "$(aws eks list-nodegroups --cluster-name o11y-cluster --region ap-northeast-1 --query 'nodegroups[0]' --output text)" --query 'nodegroup.[instanceTypes[0], scalingConfig.minSize, scalingConfig.desiredSize, scalingConfig.maxSize]' --output text --region ap-northeast-1
aws eks update-kubeconfig --name o11y-cluster --region ap-northeast-1 > /dev/null 2>&1
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' | sort -u
# o11y-cluster	1.35	ACTIVE
# t3.medium	2	2	2
# ap-northeast-1a
# ap-northeast-1c


for n in o11y-app-alb o11y-grafana-alb; do
  aws elbv2 describe-load-balancers --names $n --query 'LoadBalancers[0].[State.Code, Type, Scheme]' --output text --region ap-northeast-1
done
for n in o11y-app-tg o11y-grafana-tg; do
  aws elbv2 describe-target-health --target-group-arn "$(aws elbv2 describe-target-groups --names $n --query 'TargetGroups[0].TargetGroupArn' --output text --region ap-northeast-1)" --query 'TargetHealthDescriptions[].TargetHealth.State' --output text --region ap-northeast-1
done
# active	application	internet-facing
# active	application	internet-facing
# healthy	healthy <- Healthy 이외의 값 출력되면 오답
# healthy <- Healthy 이외의 값 출력되면 오답


kubectl get deploy log-generator -n o11y -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas'
kubectl get ds o11y-otel -n monitoring -o custom-columns='NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady'
kubectl get svc o11y-loki -n monitoring -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,PORT:.spec.ports[0].port' 
kubectl get deploy o11y-grafana -n monitoring -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas' 
# NAME            READY
# log-generator   2
# NAME        DESIRED   READY
# o11y-otel   2         2
# NAME        TYPE        PORT
# o11y-loki   ClusterIP   3100
# NAME           READY
# o11y-grafana   1
# 1 이상이고, DESIRED와 READY 값이 일치한 경우 득점 인정합니다.


ALB=$(aws elbv2 describe-load-balancers --names o11y-app-alb --query 'LoadBalancers[0].DNSName' --output text --region ap-northeast-1)
curl -s "http://$ALB/healthz"; echo
curl -s "http://$ALB/log?level=error&count=3" | head -1 | jq -r '.level, .generated'
# {"status":"ok"}
# error
# 3


echo "manual marking"
RESP=$(curl -s "http://$(aws elbv2 describe-load-balancers --names o11y-app-alb --query 'LoadBalancers[0].DNSName' --output text --region ap-northeast-1)/log?level=error&count=3")
kubectl port-forward -n monitoring svc/o11y-loki 3100:3100 > /dev/null 2>&1 &
PF=$!
sleep 2
# * 아래 명령어를 통해 로그가 정상적으로 조회되는지 확인합니다. 선수는 1분간 원하는 만큼 해당 명령어를 원하는 만큼 실행할 수 있습니다.
curl -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={k8s_namespace_name="o11y"} | json | level="ERROR"' --data-urlencode "start=$(date -d '3 minutes ago' +%s)000000000" --data-urlencode "end=$(date +%s)000000000" --data-urlencode 'limit=20' | jq -r '.data.result[].values[][1]'
# {"ts":"2026-05-31T12:26:32.805Z","level":"ERROR","msg":"log generated","req_id":"75d9896e-db0a-4b98-b859-ea6df730b04f"}
# {"ts":"2026-05-31T12:26:32.805Z","level":"ERROR","msg":"log generated","req_id":"9beba665-fb2b-4543-ade4-1cb87e793a44"}
# 출력되는 로그 중 3분 이내로 기록된 로그가 있다면 득점 인정.
# * 이후, 아래 명령어를 통해 포트포워딩 중인 프로세스를 종료합니다.
kill $PF 2>/dev/null


echo 'manual marking'
# 선수의 Grafana ALB에 접속하여, skills<선수등번호> / GoodJob!Skills<선수등번호>^^로 로그인한 뒤, Log Overview 대시보드를 엽니다.
# 1) 아래 사진과 같이 Panel 이름, 범례 등이 정상적으로 표시된다면 부분 점수 득점. (0.5점) 단, No Data로 표시되는 Panel이 하나라도 있거나, 범례가 {level="ERROR"} 등으로 표시된다면 오답 처리합니다.
# Panel은 아래 3개가 출력되어야 합니다.
# - Log Count Over Time - 막대그래프 형식의 패널
# - Log Level Distribution - 원그래프 형식의 패널
# - Recent Logs - 집계된 로그 출력

# 2) 아래 Recent Logs에 4-5에서 전송한 로그가 존재하는지 확인합니다. 존재한다면 부분 점수 득점 인정합니다 (0.5점)
# 3) Connections -> Data Sources로 접속하여 Loki Source를 선택합니다. 여러 개 있을 경우, 선수가 지정한 source를 선택합니다. (단, 선택을 바꿀 수 없습니다.) 페이지 최하단으로 이동하여 Save&Test를 클릭합니다.
# 아래와 같이 성공으로 표시되면 부분 점수 득점 인정합니다. (0.5점)