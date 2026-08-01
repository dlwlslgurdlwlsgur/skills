## header
```bash
{
    "Name": "header-block",
    "Priority": 4,
    "Statement": {
        "RegexMatchStatement": {
            "RegexString": "hacker|bad",
            "FieldToMatch": {
                "SingleHeader": {
                    "Name": "type"
                }
            },
            "TextTransformations": [
                {
                    "Priority": 0,
                    "Type": "NONE"
                }
            ]
        }
    },
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "header-block"
    },
    "Action": {
        "Block": {
            "CustomResponse": {
                "ResponseCode": 403
            }
        }
    }
}
```