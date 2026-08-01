#!/bin/bash
set -x

# 1. 캐시 정책 생성 또는 조회
cat << EOF > cache-policy.json
{
  "CachePolicyConfig": {
    "Name": "skillsphone-cdn-ab-cache-policy",
    "MinTTL": 0,
    "MaxTTL": 3600,
    "DefaultTTL": 300,
    "ParametersInCacheKeyAndForwardedToOrigin": {
      "EnableAcceptEncodingGzip": true,
      "EnableAcceptEncodingBrotli": true,
      "HeadersConfig": { "HeaderBehavior": "none" },
      "CookiesConfig": { "CookieBehavior": "whitelist", "Cookies": { "Quantity": 1, "Items": ["x-sp-ab"] } },
      "QueryStringsConfig": { "QueryStringBehavior": "none" }
    }
  }
}
EOF
CACHE_POLICY_ID=$(aws cloudfront create-cache-policy --cache-policy-config file://cache-policy.json --query 'CachePolicy.Id' --output text 2>/dev/null || aws cloudfront list-cache-policies --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='skillsphone-cdn-ab-cache-policy'].CachePolicy.Id | [0]" --output text)

# 2. 응답 헤더 정책 생성 또는 조회
cat << EOF > header-policy.json
{
  "ResponseHeadersPolicyConfig": {
    "Name": "skillsphone-cdn-ab-header-policy",
    "SecurityHeadersConfig": {
      "StrictTransportSecurity": { "Override": true, "IncludeSubdomains": true, "AccessControlMaxAgeSec": 31536000, "Preload": true },
      "ContentTypeOptions": { "Override": true },
      "FrameOptions": { "Override": true, "FrameOption": "DENY" },
      "XSSProtection": { "Override": true, "Protection": true, "ModeBlock": true }
    }
  }
}
EOF
HEADER_POLICY_ID=$(aws cloudfront create-response-headers-policy --response-headers-policy-config file://header-policy.json --query 'ResponseHeadersPolicy.Id' --output text 2>/dev/null || aws cloudfront list-response-headers-policies --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='skillsphone-cdn-ab-header-policy'].ResponseHeadersPolicy.Id | [0]" --output text)
echo ">> 확보된 헤더 정책 ID: $HEADER_POLICY_ID"

if [ -z "$HEADER_POLICY_ID" ] || [ "$HEADER_POLICY_ID" == "None" ]; then
    echo "헤더 정책을 찾거나 생성할 수 없습니다."
    exit 1
fi

# 3. 배포 ID 및 CloudFront 함수 ARN 조회
CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='skillsphone-cdn-ab-distribution'].Id | [0]" --output text)
REQ_FN_ARN=$(aws cloudfront describe-function --name skillsphone-cdn-ab-req-fn --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
RES_FN_ARN=$(aws cloudfront describe-function --name skillsphone-cdn-ab-res-fn --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

# 4. 배포 업데이트 (Cache, Header, Functions 연결)
aws cloudfront get-distribution-config --id $CF_ID > cf-config-full.json
ETAG=$(jq -r '.ETag' cf-config-full.json)
jq '.DistributionConfig' cf-config-full.json > cf-config-body.json

jq --arg cp "$CACHE_POLICY_ID" \
   --arg hp "$HEADER_POLICY_ID" \
   --arg reqFn "$REQ_FN_ARN" \
   --arg resFn "$RES_FN_ARN" \
   'del(.DefaultCacheBehavior.ForwardedValues, .DefaultCacheBehavior.MinTTL, .DefaultCacheBehavior.DefaultTTL, .DefaultCacheBehavior.MaxTTL) |
    .DefaultCacheBehavior.CachePolicyId = $cp |
    .DefaultCacheBehavior.ResponseHeadersPolicyId = $hp |
    .DefaultCacheBehavior.FunctionAssociations = {
        "Quantity": 2,
        "Items": [
            { "EventType": "viewer-request", "FunctionARN": $reqFn },
            { "EventType": "viewer-response", "FunctionARN": $resFn }
        ]
    }' cf-config-body.json > updated-cf-config.json

aws cloudfront update-distribution --id $CF_ID --if-match $ETAG --distribution-config file://updated-cf-config.json > /dev/null

rm -f cache-policy.json header-policy.json cf-config-full.json cf-config-body.json updated-cf-config.json

echo "CloudFront 배포 업데이트 완료"