```bash
export CANDIDATE_NUMBER=<비번호>
```
```bash
wget https://raw.githubusercontent.com/dlwlslgurdlwlsgur/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/Workflow/stepfunction_app.py
wget https://raw.githubusercontent.com/dlwlslgurdlwlsgur/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/Workflow/stepfunction_trigger.py
wget https://raw.githubusercontent.com/dlwlslgurdlwlsgur/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/Workflow/workflow.py
wget https://raw.githubusercontent.com/dlwlslgurdlwlsgur/skills/refs/heads/main/2%EA%B3%BC%EC%A0%9C/02/Workflow/test.csv
```
```bash
sudo dnf install -y python3-pip
python3 -m pip install --user boto3
python3 ./workflow.py
```