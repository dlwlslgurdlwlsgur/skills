## VPC
- Client VPC: pub 2
- Service VPC: pub 2, priv 2


## VPC Lattice TargetGroup
- targetGroup: skills-lattice-order-tg
- protocol/port: HTTP / 8080
- vpc: skills-lattice-service-vpc
- health: /health
- target: skills-lattice-service-ec2

## VPC Lattice Service
- name: skills-lattice-order-service
- listener: skills-lattice-http-listener
- protocol/port: HTTP / 80


## VPC Lattice Service Network
- name: skills-lattice-sn
- vpc: 2개


## service ec2
- 보안그룹 인바운드에 8080 대상 Lattice로 변경
- lattice 대상그룹에 ec2 연결
```
sudo su
cd /home/ec2-user/
yum install python3-pip -y
touch service_app.py
```
```
nohup python3 service_app.py &
```


## client ec2
- VPC Lattice 서비스 메뉴애서 도매인 복사
```
export SERVICE_URL="http://<LATTICE_SERVICE_DOMAIN>"
```
```
sudo yum install python3-pip -y
sudo -E nohup python3 client_app.py &
```