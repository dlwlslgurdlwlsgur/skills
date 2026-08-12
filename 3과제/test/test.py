import requests
import time
import sys
import threading
import random
import uuid


target_url = input("전체 URL을 입력하세요: ").strip()

if not target_url.startswith("http"):
    print("0점")
    sys.exit(1)

DURATION = 1800
START_TIME = time.time()
END_TIME = START_TIME + DURATION

lock = threading.Lock()

stats = {
    "user_pass": 0, "user_tot": 0,
    "product_pass": 0, "product_tot": 0,
    "stress_pass": 0, "stress_tot": 0,
    "image_pass": 0, "image_tot": 0,
    "def_header_pass": 0, "def_header_tot": 0,
    "def_query_pass": 0, "def_query_tot": 0,
    "def_path_pass": 0, "def_path_tot": 0
}

# 1. 방대한 악성 키워드 풀 (총 60개)
ALL_BAD_WORDS = [
    "hacker", "bad", "unknown", "admin_bypass", "drop_table", "script_alert", "etc_passwd",
    "union_select", "sleep_10", "cmd_exec", "eval_base64", "java_lang", "jndi_ldap", "struts_pwn",
    "spring_rce", "aws_keys", "metadata_api", "sql_map", "xss_test", "alert(1)", "onerror_prompt",
    "document_cookie", "cat_shadow", "bin_bash", "wget_http", "curl_bash", "nmap_scan", "dirb_scan",
    "nikto_scan", "log4j_exploit", "shellshock", "heartbleed", "auth_bypass", "priv_esc", "root_login",
    "suid_bash", "sudo_su", "id_rsa", "passwd_dump", "env_vars", "1=1", "or_true", "base64_decode",
    "php_system", "ssti_payload", "csrf_token_bypass", "ssrf_localhost", "xml_entity", "xxe_payload",
    "deserialize_java", "ldap_injection", "xpath_injection", "rfi_http", "lfi_etc", "null_byte",
    "format_string", "buffer_overflow", "heap_spray", "jwt_none", "cors_wildcard"
]

# 2. 방대한 악성 경로 풀 (총 60개)
ALL_BAD_PATHS = [
    "/v1/user/../../../etc/passwd", "/images/../config", "/v1/admin/bypass", "/v1/product/%00",
    "/.git/config", "/.env", "/wp-admin", "/wp-login.php", "/phpinfo.php", "/server-status",
    "/actuator/env", "/actuator/health", "/api/v1/users/export", "/admin/dashboard", "/manager/html",
    "/WEB-INF/web.xml", "/config.yml", "/docker-compose.yml", "/aws/credentials", "/.ssh/id_rsa",
    "/v1/auth/../../../../etc/shadow", "/api/debug", "/api/trace", "/metrics", "/prometheus",
    "/swagger-ui.html", "/v3/api-docs", "/graphql", "/test.php", "/shell.php", "/cmd.jsp",
    "/upload/eval.php", "/images/%2e%2e/%2e%2e/etc/passwd", "/v1/%252e%252e", "/cgi-bin/test-cgi",
    "/_profiler/phpinfo", "/_ignition/execute-solution", "/api/users?id=1'OR'1'='1", "/login?user=admin'--",
    "/v1/ping?ip=127.0.0.1;ls", "/.aws/credentials", "/.bash_history", "/.mysql_history", "/var/log/syslog",
    "/var/log/auth.log", "/etc/hosts", "/windows/win.ini", "/boot.ini", "/api/v1/user/1/delete",
    "/api/admin/users", "/server.js", "/package.json", "/composer.json", "/nginx.conf", "/httpd.conf",
    "/.htaccess", "/.htpasswd", "/crossdomain.xml", "/clientaccesspolicy.xml", "/api/users/find?name[$ne]=admin"
]

# 한 사이클(30분=10개 페이즈)에 사용할 60개를 무작위 셔플
RUN_BAD_WORDS = random.sample(ALL_BAD_WORDS, 60)
RUN_BAD_PATHS = random.sample(ALL_BAD_PATHS, 60)

base_png = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cce\xf8\xff\x00\x00\x04\xfe\x01\xff\x1c\x83\x82\x06\x00\x00\x00\x00IEND\xaeB`\x82'
COLORED_IMAGES = {f"color_{i}": base_png for i in range(1, 51)}

def fmt(p, t):
    pct = (p / t * 100) if t > 0 else 0.0
    return f"{p}/{t} ({pct:.1f}%)"

def user_worker():
    while time.time() < END_TIME:
        req_id = "999999999999"
        u_id = str(uuid.uuid4())
        email = "dbdump500001@example.org"
        try:
            url = f"{target_url}/v1/user?email={email}&requestid={req_id}&uuid={u_id}"
            res = requests.get(url, timeout=3)
            with lock:
                stats["user_tot"] += 1
                if res.status_code == 200: stats["user_pass"] += 1
        except:
            with lock: stats["user_tot"] += 1
        time.sleep(random.uniform(0.05, 0.2))

def product_worker():
    while time.time() < END_TIME:
        try:
            data = {"requestid": "999999999999", "uuid": str(uuid.uuid4()), "id": "dbdump500001"}
            color_name, img_bytes = random.choice(list(COLORED_IMAGES.items()))
            files = {'image': (f'product_{color_name}.png', img_bytes, 'image/png')}
            res = requests.put(f"{target_url}/v1/product", data=data, files=files, timeout=3)
            with lock:
                stats["product_tot"] += 1
                if res.status_code == 200: stats["product_pass"] += 1
        except:
            with lock: stats["product_tot"] += 1
        time.sleep(random.uniform(0.05, 0.2))

def stress_worker():
    while time.time() < END_TIME:
        try:
            payload = {"requestid": "999999999999", "uuid": str(uuid.uuid4()), "length": 256}
            res = requests.post(f"{target_url}/v1/stress", json=payload, timeout=3)
            with lock:
                stats["stress_tot"] += 1
                if res.status_code == 201: stats["stress_pass"] += 1
        except:
            with lock: stats["stress_tot"] += 1
        time.sleep(random.uniform(0.05, 0.2))

def image_download_worker():
    while time.time() < END_TIME:
        color_name = random.choice(list(COLORED_IMAGES.keys()))
        try:
            res = requests.get(f"{target_url}/images/product_{color_name}.png", timeout=3)
            with lock:
                stats["image_tot"] += 1
                if res.status_code == 200: stats["image_pass"] += 1
        except:
            with lock: stats["image_tot"] += 1
        time.sleep(random.uniform(0.05, 0.2))

def attack_worker():
    while time.time() < END_TIME:
        time.sleep(random.uniform(0.1, 2.5)) # 공격 딜레이도 변칙적으로
        
        elapsed = time.time() - START_TIME
        # 3분(180초) 단위로 Phase 변경 (0 ~ 9)
        phase = min(int(elapsed // 180), 9)
        
        # 이번 Phase에 할당된 6개의 공격 벡터 슬라이싱
        start_idx = phase * 6
        current_words = RUN_BAD_WORDS[start_idx : start_idx+6]
        current_paths = RUN_BAD_PATHS[start_idx : start_idx+6]
        
        # 복합 공격 추가 (header, query, path, combo)
        attack_type = random.choice(["header", "query", "path", "combo"])
        rand_word = random.choice(current_words)
        
        try:
            if attack_type == "header":
                headers = {"type": rand_word}
                res = requests.get(f"{target_url}/v1/product?id=normal", headers=headers, timeout=3)
                with lock:
                    stats["def_header_tot"] += 1
                    if res.status_code == 403: stats["def_header_pass"] += 1
                        
            elif attack_type == "query":
                res = requests.get(f"{target_url}/v1/product?id={rand_word}", timeout=3)
                with lock:
                    stats["def_query_tot"] += 1
                    if res.status_code == 403: stats["def_query_pass"] += 1
            
            elif attack_type == "combo":
                # 헤더와 쿼리 둘 다 악성 데이터 전송
                word2 = random.choice(current_words)
                headers = {"type": rand_word}
                res = requests.post(f"{target_url}/v1/product?id={word2}", headers=headers, timeout=3)
                with lock:
                    stats["def_header_tot"] += 1
                    stats["def_query_tot"] += 1
                    if res.status_code == 403: 
                        stats["def_header_pass"] += 1
                        stats["def_query_pass"] += 1

            elif attack_type == "path":
                bad_path = random.choice(current_paths)
                # GET뿐만 아니라 POST, PUT, DELETE, OPTIONS 등 변칙적인 메서드 시도
                bad_method = random.choice(["GET", "POST", "PUT", "DELETE", "OPTIONS"])
                res = requests.request(bad_method, f"{target_url}{bad_path}", timeout=3)
                with lock:
                    stats["def_path_tot"] += 1
                    if res.status_code not in [200, 201]: stats["def_path_pass"] += 1

        except:
            with lock:
                if attack_type == "header": stats["def_header_tot"] += 1
                elif attack_type == "query": stats["def_query_tot"] += 1
                elif attack_type == "combo": 
                    stats["def_header_tot"] += 1
                    stats["def_query_tot"] += 1
                elif attack_type == "path": stats["def_path_tot"] += 1

threads = []
workers = [user_worker, product_worker, stress_worker, image_download_worker, attack_worker]

for worker_func in workers:
    thread_count = 3 if worker_func == attack_worker else 8
    for _ in range(thread_count):
        t = threading.Thread(target=worker_func)
        t.daemon = True
        t.start()
        threads.append(t)

try:
    current_phase = -1
    while time.time() < END_TIME:
        time.sleep(10)
        now = time.time()
        elapsed = int(now - START_TIME)
        remains = int(END_TIME - now)
        
        phase = min(elapsed // 180, 9)
        
        with lock:
            if phase != current_phase:
                start_idx = phase * 6

            print(f"⏱️ [진행: {elapsed//60:02d}분 {elapsed%60:02d}초 | 남은시간: {remains//60:02d}분 {remains%60:02d}초]")
            print(f"   ▶ 가동률 - User: {fmt(stats['user_pass'], stats['user_tot'])} | Product: {fmt(stats['product_pass'], stats['product_tot'])} | Stress: {fmt(stats['stress_pass'], stats['stress_tot'])} | 이미지DL: {fmt(stats['image_pass'], stats['image_tot'])}")
            print(f"   ▶ 방어률 - Header: {fmt(stats['def_header_pass'], stats['def_header_tot'])} | Query: {fmt(stats['def_query_pass'], stats['def_query_tot'])} | Path: {fmt(stats['def_path_pass'], stats['def_path_tot'])}")
            print("-" * 50)
except KeyboardInterrupt:
    print("\n채점이 중단되었습니다.")

print("\n===================================================")
print("평가 종료! 세부 지표별 최종 결과를 집계합니다.")
print("===================================================")

print("가동률 상세 현황 (통과/요청 수)")
print(f" - User API        : {fmt(stats['user_pass'], stats['user_tot'])}")
print(f" - Product API     : {fmt(stats['product_pass'], stats['product_tot'])}")
print(f" - Stress API      : {fmt(stats['stress_pass'], stats['stress_tot'])}")
print(f" - Image Download  : {fmt(stats['image_pass'], stats['image_tot'])}")
print("---------------------------------------------------")
print("보안 방어률 상세 현황 (차단/공격 수)")
print(f" - Header 방어     : {fmt(stats['def_header_pass'], stats['def_header_tot'])}")
print(f" - Query 방어      : {fmt(stats['def_query_pass'], stats['def_query_tot'])}")
print(f" - Path 방어       : {fmt(stats['def_path_pass'], stats['def_path_tot'])}")
print("===================================================")