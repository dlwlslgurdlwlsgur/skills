#!/bin/bash
set -x

cat << EOF > cache-policy.json
{
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
EOF
CACHE_POLICY_ID=$(aws cloudfront create-cache-policy --cache-policy-config file://cache-policy.json --query 'CachePolicy.Id' --output text 2>/dev/null || aws cloudfront list-cache-policies --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='skillsphone-cdn-ab-cache-policy'].CachePolicy.Id | [0]" --output text)

cat << EOF > header-policy.json
{
  "ResponseHeadersPolicyConfig": {
    "Name": "skillsphone-cdn-ab-header-policy",
    "SecurityHeadersConfig": {
      "StrictTransportSecurity": { "Override": true, "IncludeSubdomains": true, "MaxAgeSec": 31536000, "Preload": true },
      "ContentTypeOptions": { "Override": true },
      "FrameOptions": { "Override": true, "FrameOption": "DENY" },
      "XSSProtection": { "Override": true, "Protection": true, "ModeBlock": true }
    }
  }
}
EOF
HEADER_POLICY_ID=$(aws cloudfront create-response-headers-policy --response-headers-policy-config file://header-policy.json --query 'ResponseHeadersPolicy.Id' --output text 2>/dev/null || aws cloudfront list-response-headers-policies --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='skillsphone-cdn-ab-header-policy'].ResponseHeadersPolicy.Id" --output text)

CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='skillsphone-cdn-ab-distribution'].Id | [0]" --output text)
REQ_FN_ARN=$(aws cloudfront describe-function --name skillsphone-cdn-ab-req-fn --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
RES_FN_ARN=$(aws cloudfront describe-function --name skillsphone-cdn-ab-res-fn --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

CACHE_POLICY_ID=$(aws cloudfront list-cache-policies --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='skillsphone-cdn-ab-cache-policy'].CachePolicy.Id | [0]" --output text)

cat << 'EOF' > header-policy.json
{
  "Name": "skillsphone-cdn-ab-header-policy",
  "SecurityHeadersConfig": {
    "StrictTransportSecurity": { "Override": true, "IncludeSubdomains": true, "AccessControlMaxAgeSec": 31536000, "Preload": true },
    "ContentTypeOptions": { "Override": true },
    "FrameOptions": { "Override": true, "FrameOption": "DENY" },
    "XSSProtection": { "Override": true, "Protection": true, "ModeBlock": true }
  }
}
EOF

aws cloudfront create-response-headers-policy --response-headers-policy-config file://header-policy.json > /dev/null 2>&1
HEADER_POLICY_ID=$(aws cloudfront list-response-headers-policies --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='skillsphone-cdn-ab-header-policy'].ResponseHeadersPolicy.Id | [0]" --output text)
echo ">> 확보된 헤더 정책 ID: $HEADER_POLICY_ID"

if [ -z "$HEADER_POLICY_ID" ] || [ "$HEADER_POLICY_ID" == "None" ]; then
    aws cloudfront create-response-headers-policy --response-headers-policy-config file://header-policy.json
    exit 1
fi

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

rm -f cf-config-full.json cf-config-body.json updated-cf-config.json header-policy.json

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

aws cloudfront update-distribution --id $CF_ID --if-match $ETAG --distribution-config file://updated-cf-config.json >/dev/null

echo