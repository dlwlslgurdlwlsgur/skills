## S3
- name: skillsphone-landing-ab-<ACCOUNT_ID 12자리>
- folder: version-a, version-b
- file 이름 index.html로 변경
```
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "<S3_ARN>>/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "<CF_ARN>"
                }
            }
        }
    ]
}
```


## CloudFront
- name: skillsphone-cdn-ab-distribution


## CF Function ( KeyValueStores )
- name: skillsphone-cdn-ab-config
- Key value pairs 설정


## CF Function ( Viewer Request ) 
- name: skillsphone-cdn-ab-req-fn
- Associated KeyValueStore 연결하기
```
import cf from 'cloudfront';

const kvsHandle = cf.kvs(); 

async function handler(event) {
    const request = event.request;
    const cookies = request.cookies;
    let assignedVersion = ''; 
    let finalPath = '';

    if (cookies && cookies['x-sp-ab'] && cookies['x-sp-ab'].value) {
        assignedVersion = cookies['x-sp-ab'].value;
    } else {
        try {
            const weightRaw = await kvsHandle.get('weight');
            
            let weight = parseFloat(weightRaw.trim());
            if (isNaN(weight)) {
                weight = 0.3; 
            }
            
            if (Math.random() < weight) {
                assignedVersion = 'b';
            } else {
                assignedVersion = 'a';
            }
        } catch (err) {
            assignedVersion = 'a';
        }
        
        request.headers['x-sp-ab-assigned'] = { value: assignedVersion };
    }

    try {
        if (assignedVersion === 'b') {
            finalPath = await kvsHandle.get('version_b');
        } else {
            finalPath = await kvsHandle.get('version_a');
        }
        finalPath = finalPath.trim();
    } catch (e) {
        finalPath = '/version-a/index.html';
    }

    request.uri = finalPath;
    return request;
}
```


## CF Function ( Viewer Response ) 
- name: skillsphone-cdn-ab-res-fn
```
function handler(event) {
    const request = event.request;
    const response = event.response;
    
    if (request.headers['x-sp-ab-assigned'] && request.headers['x-sp-ab-assigned'].value) {
        const assignedVersion = request.headers['x-sp-ab-assigned'].value;
        
        response.cookies['x-sp-ab'] = {
            value: assignedVersion,
            attributes: "Path=/; Max-Age=86400"
        };
    }
    
    return response;
}
```


## CF Cache Policy
- name: skillsphone-cdn-ab-cache-policy
- 최소/기본/최대 조심
- cookie 허용: x-sp-ab


## CF Header Policy
- name: skillsphone-cdn-ab-header-policy
- Strict-Transport-Security: ON
- X-Content-Type-Options: ON
- X-Content-Type-Options: ON, DENY
- X-XSS-Protection: ON, mode=block