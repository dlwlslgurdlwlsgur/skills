## header
```bash
{
    "Name": "header-hacker",
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
        "MetricName": "header-hacker"
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