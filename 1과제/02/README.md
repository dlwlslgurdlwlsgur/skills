## shell
- 01-vpc.sh
- 02-kms.sh
- 03-cluster.sh

<br>

## S3
- wskorea26-concert-bucket-<비번호>
- /web/main/
- KMS
```bash
aws s3 rm s3://$BUCKET/web/main/
```

<br>

## shell
- 배포파일/book
- 04-ecr.sh
- 05-dynamodb.sh


<br>

## Lambda
- wskorea26-book-lambda
- Python 3.14
- 30초
- 환경변수 { TABLE_NAME: wskorea26-data-table }

<br>

## app
- 06-app.sh

<br>

## CF
- wskorea26-concert-cf
- name: wskorea26-s3-origin ( * )
- /web/main
- S3 원본 > 사용자 정의 헤더 ( wskorea26-s3-access: true )
- S3 OAC, KMS

- name: wskorea26-alb-origin ( /book* )
- ALB 원본 > 사용자 정의 헤더 ( X-Origin-Verify: wskorea26-cf )
- ALB 동작 > 쿼리 문자열 모두

<br>

## monitoring
```bash
export BNUM=<비번호>
```
- 07-monitoring.sh