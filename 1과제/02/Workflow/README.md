## Region
- 싱가포르/ap-southeast-1

<br>

## 환경변수
```bash
export CANDIDATE_NUMBER=<비번호>
```

<br>

## template
배포파일/test.csv
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/02/Workflow/stepfunction_app.py
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/02/Workflow/stepfunction_trigger.py
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/1%EA%B3%BC%EC%A0%9C/02/Workflow/workflow.py
```

<br>

## python
```bash
sudo dnf install -y python3-pip
python3 -m pip install --user boto3
```
```bash
python3 ./workflow.py
```

<br>

## 채점
- s3
- dynamodb