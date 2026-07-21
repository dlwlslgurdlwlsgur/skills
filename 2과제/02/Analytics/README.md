## Kinesis
- kinesis stream을 대상으로 Glue Table ( json )


## Kinesis flink
- kinesis flink는 VPC 없이하고 병렬 2개
```
%flink.ssql

CREATE TABLE order_stream (
    product_name STRING,
    price DOUBLE,
    quantity INT,
    event_time TIMESTAMP(3),
    WATERMARK FOR event_time AS event_time - INTERVAL '3' SECOND 
) WITH (
    'connector' = 'kinesis',
    'stream' = 'wsc2026-order-stream',
    'aws.region' = 'ap-northeast-2',
    'scan.stream.init-position' = 'LATEST',
    'format' = 'json'
);

```
```
%flink.ssql

SELECT COUNT(*) as order_count 
FROM order_stream 
WHERE event_time > CURRENT_TIMESTAMP - INTERVAL '1' MINUTE;
```
```
%flink.ssql

SELECT product_name, SUM(price * quantity) as total_revenue 
FROM order_stream 
GROUP BY product_name;
```


## ec2에서 app 실행
```
sudo su
mkdir /opt/app
cd /opt/app
yum install python3-pip -y
pip3 install flask boto3 gunicorn
```
```
sudo tee /etc/systemd/system/app.service > /dev/null << 'EOF'
[Unit]
Description=Flask Application for Grading
After=network.target

[Service]
User=root
WorkingDirectory=/opt/app
Environment="STREAM_NAME=wsc2026-order-stream"
Environment="AWS_REGION=ap-northeast-2"
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable app
sudo systemctl start app
```