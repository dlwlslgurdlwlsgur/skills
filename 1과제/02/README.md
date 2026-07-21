## shell
- 04-ecr.sh
- 05-dynamodb.sh

<br>

## Lambda
- wskorea26-book-lambda
- Python 3.14
- 환경변수 설정 ( wskorea26-data-table )

<br>

## S3
- wskorea26-concert-bucket-<비번호>
- /web/main/
- KMS
```bash
aws s3 rm s3://$BUCKET/web/main/
```

<br>

## app
- 06-app.sh

<br>

## CF
- wskorea26-concert-cf
- wskorea26-s3-origin ( * )
- S3 원본 > 사용자 정의 헤더 ( wskorea26-s3-access: true )

- wskorea26-alb-origin ( /book* )
- ALB 원본 > 사용자 정의 헤더 ( X-Origin-Verify: wskorea26-cf )
- ALB 동작 > 쿼리 문자열 모두

<br>

## monitoring
- 비번호 설정
- 07-monitoring.sh
```bash
export BNUM=<비번호>
```