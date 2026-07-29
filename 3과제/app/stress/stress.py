import os
import json
import hashlib
from flask import Flask, request, jsonify

app = Flask(__name__)

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
    valid_paths = ["/v1/stress", "/healthcheck"]
    if request.path not in valid_paths:
        return jsonify({"error": "not_found"}), 404
    if request.path != "/healthcheck" and detect_threat(request):
        return jsonify({"error": "forbidden"}), 403

@app.route("/v1/stress", methods=["POST"])
def stress_api():
    data = request.json or {}
    length = data.get("length", 100)
    
    seed = os.urandom(16)
    for _ in range(length):
        hashlib.sha256(seed).hexdigest()
        
    return jsonify({"status": "stress_completed", "length": length}), 201

@app.route("/healthcheck", methods=["GET"])
def healthcheck():
    return "ok", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)