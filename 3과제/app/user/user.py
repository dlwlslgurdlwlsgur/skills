import os
import json
import uuid
import pymysql
from flask import Flask, request, jsonify

app = Flask(__name__)

def get_db_connection():
    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST"),
        user=os.environ.get("MYSQL_USER"),
        password=os.environ.get("MYSQL_PASSWORD"),
        database=os.environ.get("MYSQL_DBNAME", "wsc2026db"),
        cursorclass=pymysql.cursors.DictCursor
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
    valid_paths = ["/v1/user", "/healthcheck"]
    if request.path not in valid_paths:
        return jsonify({"error": "not_found"}), 404
    if request.path != "/healthcheck" and detect_threat(request):
        return jsonify({"error": "forbidden"}), 403

@app.route("/v1/user", methods=["GET", "POST"])
def user_api():
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            if request.method == "POST":
                data = request.json or {}
                uid = uuid.uuid4().hex
                cur.execute("INSERT INTO user (id, username, email) VALUES (%s, %s, %s)", 
                            (uid, data.get('username'), data.get('email')))
                conn.commit()
                return jsonify({"id": uid, "username": data.get('username'), "email": data.get('email')}), 201
            else:
                email = request.args.get("email")
                # 커버링 인덱스를 활용하기 위해 필요한 컬럼만 SELECT
                cur.execute("SELECT id, username, email FROM user WHERE email=%s", (email,))
                row = cur.fetchone()
                return jsonify(row) if row else (jsonify({"error": "not_found"}), 404)
    finally:
        conn.close()

@app.route("/healthcheck", methods=["GET"])
def healthcheck():
    return "ok", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)