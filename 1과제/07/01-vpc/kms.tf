# 1. CloudFront, WAF 등에서 사용할 Platform CMK (Multi-Region Primary)
resource "aws_kms_key" "platform_primary" {
  provider                = aws.us_east_1 # 반드시 us-east-1 (providers.tf에 정의된 alias)
  description             = "Platform CMK Primary Key (us-east-1)"
  multi_region            = true
  enable_key_rotation     = true
  rotation_period_in_days = 90 # 🚨 90일 주기 설정 추가
  is_enabled              = true
  deletion_window_in_days = 7
}

# 2. EKS, CloudWatch 등에서 사용할 Platform CMK Replica (ap-northeast-2)
resource "aws_kms_replica_key" "platform_replica" {
  description     = "Platform CMK Replica Key (ap-northeast-2)"
  primary_key_arn = aws_kms_key.platform_primary.arn
  # (Replica 키는 Primary 키의 회전 설정을 자동으로 상속받습니다)
}

# 3. 데이터베이스(DynamoDB) 암호화 등에 사용할 App Key
resource "aws_kms_key" "app" {
  description             = "Application KMS Key"
  enable_key_rotation     = true
  rotation_period_in_days = 90 # 🚨 90일 주기 설정 추가
  is_enabled              = true
  deletion_window_in_days = 7
}

# 4. ECR 이미지 암호화 등에 사용할 Data Key
resource "aws_kms_key" "data" {
  description             = "Data KMS Key"
  enable_key_rotation     = true
  rotation_period_in_days = 90 # 🚨 90일 주기 설정 추가
  is_enabled              = true
  deletion_window_in_days = 7
}

# ------------------------------------------------------------------
# 5. KMS 별칭 (Alias) 리소스 - 🚨 app, data 별칭 추가 완료!
# ------------------------------------------------------------------
resource "aws_kms_alias" "replica_alias" {
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_replica_key.platform_replica.key_id
}

resource "aws_kms_alias" "app_alias" {
  name          = "alias/unicorn-kms-app"
  target_key_id = aws_kms_key.app.key_id
}

resource "aws_kms_alias" "data_alias" {
  name          = "alias/unicorn-kms-data"
  target_key_id = aws_kms_key.data.key_id
}