# MSK 과제 최종 실행 가이드

이 가이드가 최종본입니다. 기존 `msk_solution_guide.md`의 수동 AWS CLI 생성 절차는 사용하지 않습니다.

실행 파일:

```text
msk_paste_once.sh
```

이 스크립트는 빈 변수 연쇄 오류를 막고 기존 리소스를 이름으로 재조회하며, NAT/MSK/Lambda/이벤트 매핑의 준비 상태를 기다립니다.

## 1. 사전 확인

원격 Amazon Linux 서버에서 AWS 계정과 리전을 확인합니다.

```bash
export AWS_DEFAULT_REGION="ap-northeast-1"
aws configure set region "$AWS_DEFAULT_REGION"
aws sts get-caller-identity
```

비번호를 반드시 설정합니다. 아래 `1`은 예시이므로 실제 비번호로 변경합니다.

```bash
export EXAM_NO="1"
```

버킷 이름:

```text
wsc2026-sensor-alert-bucket-<비번호>
```

## 2. 파일 업로드

Windows PowerShell에서 `<PUBLIC_IP>`를 원격 서버 IP로 변경합니다.

```powershell
scp ".\2과제\msk_paste_once.sh" ec2-user@<PUBLIC_IP>:/home/ec2-user/msk_paste_once.sh
ssh ec2-user@<PUBLIC_IP>
```

원격 서버에서 줄바꿈과 구문을 검사합니다.

```bash
tr -d '\r' < /home/ec2-user/msk_paste_once.sh > /tmp/msk_paste_once.sh
mv /tmp/msk_paste_once.sh /home/ec2-user/msk_paste_once.sh
chmod +x /home/ec2-user/msk_paste_once.sh
bash -n /home/ec2-user/msk_paste_once.sh
echo $?
```

마지막 출력이 `0`이어야 합니다.

## 3. 전체 실행

비번호가 `1`인 예:

```bash
export EXAM_NO="1"
export AWS_DEFAULT_REGION="ap-northeast-1"
bash /home/ec2-user/msk_paste_once.sh 2>&1 | tee /home/ec2-user/msk_setup.log
```

실행 규칙:

- 실행 중 다른 생성 명령을 입력하지 않습니다.
- MSK 생성은 15~30분 걸릴 수 있습니다.
- `MSK state: CREATING`은 정상입니다.
- 오류가 발생하면 스크립트가 즉시 중단됩니다.
- 실패 이후 단계를 수동으로 이어서 실행하지 않습니다.

SSH 연결이 불안정하면 다음처럼 실행합니다.

```bash
nohup env EXAM_NO="1" AWS_DEFAULT_REGION="ap-northeast-1" \
  bash /home/ec2-user/msk_paste_once.sh \
  > /home/ec2-user/msk_setup.log 2>&1 < /dev/null &
```

진행 로그:

```bash
less +F /home/ec2-user/msk_setup.log
```

완료 여부:

```bash
pgrep -af msk_paste_once.sh || echo "setup process finished"
```

## 4. 중간 확인

### MSK

```bash
CLUSTER_ARN=$(aws kafka list-clusters-v2 \
  --cluster-name-filter wsc2026-msk-cluster \
  --query "ClusterInfoList[0].ClusterArn" --output text)

aws kafka describe-cluster \
  --cluster-arn "$CLUSTER_ARN" \
  --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" \
  --output text
```

완료 상태:

```text
wsc2026-msk-cluster	ACTIVE	3.6.0	kafka.t3.small	True
```

### Lambda와 트리거

```bash
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  aws lambda get-function \
    --function-name "$fn" \
    --query "Configuration.[FunctionName,Runtime,State,LastUpdateStatus]" \
    --output text
done
```

두 함수 모두 `python3.14`, `Active`, `Successful`이어야 합니다.

```bash
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  aws lambda list-event-source-mappings \
    --function-name "$fn" \
    --query "EventSourceMappings[0].[State,LastProcessingResult]" \
    --output text
done
```

두 줄의 첫 번째 값이 모두 `Enabled`여야 합니다.

## 5. 최종 채점 준비

SSH 재접속 후에도 이 블록으로 변수를 복구할 수 있습니다.

```bash
export AWS_DEFAULT_REGION="ap-northeast-1"
export EXAM_NO="1"

: "${EXAM_NO:?Set EXAM_NO first}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="wsc2026-sensor-alert-bucket-${EXAM_NO}"
TOPIC_ARN="arn:aws:sns:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:wsc2026-sensor-alert"
CLUSTER_ARN=$(aws kafka list-clusters-v2 \
  --cluster-name-filter wsc2026-msk-cluster \
  --query "ClusterInfoList[0].ClusterArn" --output text)

test -n "$ACCOUNT_ID" && test "$ACCOUNT_ID" != "None"
test -n "$CLUSTER_ARN" && test "$CLUSTER_ARN" != "None"
```

### 4-1

```bash
aws dynamodb describe-table \
  --table-name wsc2026-sensor-data \
  --query "Table.[TableName,KeySchema[*].AttributeName]" --output text

aws s3api head-bucket --bucket "$BUCKET_NAME"

aws sns get-topic-attributes \
  --topic-arn "$TOPIC_ARN" \
  --query "Attributes.TopicArn" --output text
```

### 4-2

```bash
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  aws lambda get-function \
    --function-name "$fn" \
    --query "Configuration.[FunctionName,Runtime]" --output text
done
```

기대값:

```text
wsc2026-sensor-consumer	python3.14
wsc2026-sensor-alert-consumer	python3.14
```

### 4-3

```bash
aws kafka describe-cluster \
  --cluster-arn "$CLUSTER_ARN" \
  --query "ClusterInfo.[ClusterName,State,CurrentBrokerSoftwareInfo.KafkaVersion,BrokerNodeGroupInfo.InstanceType,ClientAuthentication.Sasl.Iam.Enabled]" \
  --output text
```

기대값:

```text
wsc2026-msk-cluster	ACTIVE	3.6.0	kafka.t3.small	True
```

### 4-4

```bash
for fn in wsc2026-sensor-consumer wsc2026-sensor-alert-consumer; do
  aws lambda list-event-source-mappings \
    --function-name "$fn" \
    --query "EventSourceMappings[0].[State]" --output text
done
```

기대값:

```text
Enabled
Enabled
```

### 4-5

```bash
aws dynamodb scan \
  --table-name wsc2026-sensor-data \
  --max-items 1 \
  --query "Items[0].{sensorId:sensorId.S,temperature:temperature.S,status:status.S}" \
  --output json
```

기대값:

```json
{
  "sensorId": "SENSOR-002",
  "temperature": "64.6",
  "status": "NORMAL"
}
```

### 4-6

```bash
aws dynamodb scan \
  --table-name wsc2026-sensor-data \
  --max-items 3 \
  --query "Items[*].{sensorId:sensorId.S,timestamp:timestamp.S}" \
  --output table
```

기대값:

```text
---------------------------------------------
|                   Scan                    |
+-------------+-----------------------------+
|  sensorId   |          timestamp          |
+-------------+-----------------------------+
|  SENSOR-002 |  2026-06-01T18:28:24+09:00  |
+-------------+-----------------------------+
```

## 6. 오류 처리

- ID가 빈 값이면 다음 단계로 진행하지 않습니다.
- `MSK state: CREATING`은 정상 대기 상태입니다.
- `existing MSK cluster uses different or deleted network resources`가 나오면 기존 MSK를 재사용하면 안 됩니다.
- `Topic does not exist`가 나오면 Producer 초기 설정 단계의 최초 오류를 확인합니다.
- `0.0.0.0/0aws ec2 ...`처럼 명령이 붙었다면 잘못된 수동 입력입니다.
- 완성된 환경에서 전체 스크립트를 불필요하게 다시 실행하지 않습니다.
- 마지막 단계는 `wsc2026-sensor-data` 테이블을 채점 데이터로 재생성합니다.

## 7. 보안

AWS Access Key와 Secret Access Key를 터미널 캡처나 대화에 노출하지 않습니다. 노출된 키는 즉시 비활성화하고 새 키를 발급합니다.
