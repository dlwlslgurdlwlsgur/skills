## DynamoDB
- ReservationTable: bigbae-nosql-reservation-table
- AuditTable: bigbae-nosql-audit-table
- PITR 활성화
- 스트림 활성화


## Lambda
- name: bigbae-nosql-reservation-audit
- handler 변경
- 30초


## EC2
- name: bigbae-nosql-app-ec2
```
sudo yum install python3-pip -y
pip3 install --ignore-installed -r requirements.txt
pip3 install "jmespath<1.1.0,>=0.7.1" "python-dateutil<=2.9.0,>=2.1"
export AWS_REGION="ap-southeast-1"
export TABLE_NAME="bigbae-nosql-reservation-table"
export GSI_NAME="gsi-user-reservations"
nohup python3 app.py &
```