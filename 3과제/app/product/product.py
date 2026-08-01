import os
import json
import pymysql
from flask import Flask, request, jsonify

app = Flask(__name__)

def get_db_connection():
    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST"),
        user=os.environ.get("MYSQL_USER"),
        password=os.environ.get("MYSQL_PASSWORD"),
        database=os.environ.get("MYSQL_DBNAME", "wsc2026db"),
        cursorclass=pymysql.cursors.DictCursor,
        ssl={"check_hostname": False} # 반드시 추가 (TLS 암호화 연결 활성화)
    )

def detect_threat(req):
    threat_keywords = ["hacker", "union select", "1=1", "script", "etc/passwd"]
    for k, v in req.headers.items():
        if any(tk in str(v).lower() for tk in threat_keywords) or any(tk in k.lower() for tk in threat_keywords):
            print(json.dumps({"level": "WARN", "type": "THREAT_HEADER", "header": k, "value": v}), flush=True)
            return True
    for k, v in req.args.items():
        if any(tk in str(v).lower() for tk in threat_keywords):
            print(json.dumps({"level": "WARN", "type": "THREAT_QUERY", "key": k, "value": v}), flush=True)
            return True
    return False

@app.before_request
def before_request():
    valid_paths = ["/v1/product", "/healthcheck"]
    if request.path not in valid_paths:
        return jsonify({"error": "not_found"}), 404
    if request.path != "/healthcheck" and detect_threat(request):
        return jsonify({"error": "forbidden"}), 403

@app.route("/v1/product", methods=["GET", "POST", "PUT"])
def product_api():
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            if request.method == "POST":
                data = request.json or {}
                pid = data.get('id')
                cur.execute("INSERT INTO product (id, name, price) VALUES (%s, %s, %s)", 
                            (pid, data.get('name'), data.get('price')))
                conn.commit()
                return jsonify({"id": pid, "name": data.get('name'), "price": data.get('price')}), 201
            
            elif request.method == "PUT":
                pid = request.form.get("id") or request.args.get("id")
                file = request.files.get("file") or request.files.get("image")
                if not file or not pid:
                    return jsonify({"error": "bad_request"}), 400

                filename = file.filename
                s3_bucket = os.environ.get("S3_BUCKET")

                # 1. 환경 변수(S3_BUCKET)가 있으면 Boto3를 이용해 S3에 직접 업로드
                if s3_bucket:
                    import boto3
                    s3_region = os.environ.get("AWS_REGION", "ap-northeast-2")
                    s3_client = boto3.client("s3", region_name=s3_region)
                    s3_key = f"images/{filename}"
                    s3_client.upload_fileobj(file, s3_bucket, s3_key, ExtraArgs={"ContentType": file.mimetype})
                    image_path = f"/{filename}"
                
                # 2. 환경 변수가 없으면 로컬 폴더(/images)에 저장 (마운트 방식 호환)
                else:
                    os.makedirs("/images", exist_ok=True)
                    local_path = os.path.join("/images", filename)
                    file.save(local_path)
                    image_path = f"/{filename}"

                cur.execute("UPDATE product SET image_path=%s WHERE id=%s", (image_path, pid))
                conn.commit()
                
                return jsonify({"id": pid, "image_path": image_path}), 200

            else: # GET
                pid = request.args.get("id")
                cur.execute("SELECT id, name, price, image_path FROM product WHERE id=%s", (pid,))
                row = cur.fetchone()
                return jsonify(row) if row else (jsonify({"error": "not_found"}), 404)
    finally:
        conn.close()

@app.route("/healthcheck", methods=["GET"])
def healthcheck():
    return "ok", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)