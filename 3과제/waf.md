## header
```bash
{
    "Name": "header",
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
        "MetricName": "header"
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

<br>

## query
```bash
{
    "Name": "query",
    "Priority": 5,
    "Statement": {
        "RegexMatchStatement": {
        "RegexString": "hacker|bad",
        "FieldToMatch": {
            "QueryString": {}
        },
        "TextTransformations": [
            {
            "Priority": 0,
            "Type": "LOWERCASE"
            },
            {
            "Priority": 1,
            "Type": "URL_DECODE"
            }
        ]
        }
    },
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "query"
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

<br>

# path
```bash
{
    "Name": "path",
    "Priority": 6,
    "Statement": {
        "OrStatement": {
        "Statements": [
            {
            "ByteMatchStatement": {
                "SearchString": "/v1/bad",
                "FieldToMatch": { "UriPath": {} },
                "TextTransformations": [{ "Priority": 0, "Type": "NONE" }],
                "PositionalConstraint": "EXACTLY"
            }
            },
            {
            "ByteMatchStatement": {
                "SearchString": "/v1/hacker",
                "FieldToMatch": { "UriPath": {} },
                "TextTransformations": [{ "Priority": 0, "Type": "NONE" }],
                "PositionalConstraint": "EXACTLY"
            }
            }
        ]
        }
    },
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "path"
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

<br>

# body
```bash
{
    "Name": "body",
    "Priority": 7,
    "Statement": {
        "OrStatement": {
        "Statements": [
            {
            "RegexMatchStatement": {
                "RegexString": "\"KEY\"\\s*:\\s*\"[^\"]*VALUE[^\"]*\"",
                "FieldToMatch": {
                "Body": {
                    "OversizedHandling": "MATCH"
                }
                },
                "TextTransformations": [
                { "Priority": 0, "Type": "LOWERCASE" }
                ]
            }
            },
            {
            "RegexMatchStatement": {
                "RegexString": "\"KEY\"\\s*:\\s*\"[^\"]*VALUE[^\"]*\"",
                "FieldToMatch": {
                "Body": {
                    "OversizedHandling": "MATCH"
                }
                },
                "TextTransformations": [
                { "Priority": 0, "Type": "LOWERCASE" }
                ]
            }
            }
        ]
        }
    },
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "body"
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