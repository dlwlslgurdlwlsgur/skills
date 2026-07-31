import requests
import time
import sys
import threading
import random
import uuid

print("===================================================")
print("🔥 2026년 전국대회 3과제 [공식 규격] 자동 채점 시스템 🔥")
print("===================================================")

target_url = input("👉 평가할 대상의 전체 URL을 입력하세요 (예: http://alb-주소...): ").strip()

if not target_url.startswith("http"):
    print("❌ 오류: 프로토콜(http:// 또는 https://)을 포함해서 다시 실행해 주세요!")
    sys.exit(1)

print(f"\n✅ 타겟 설정 완료: {target_url}")
print("⏳ 지금부터 30분(1800초) 동안 공식 규격(requestid, uuid, PUT 이미지 등)으로 평가를 시작합니다...")
print("===================================================")

DURATION = 1800
START_TIME = time.time()
END_TIME = START_TIME + DURATION

lock = threading.Lock()
stats = {
    "user_success": 0,
    "user_fail": 0,
    "product_success": 0,
    "product_fail": 0,
    "stress_success": 0,
    "stress_fail": 0,
    "image_success": 0,
    "image_fail": 0,
    "attack_blocked": 0,
    "attack_missed": 0
}

BAD_WORDS = ["hacker", "bad", "unknown", "admin_bypass", "drop_table", "script_alert", "etc_passwd"]

# 코드로 생성한 Red, Blue, Yellow 1x1 픽셀 PNG 바이트[cite: 1]
COLORED_IMAGES = {
    "red": b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cce\xf8\xff\x00\x00\x04\xfe\x01\xff\x1c\x83\x82\x06\x00\x00\x00\x00IEND\xaeB`\x82',
    "blue": b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xfb\xcf\x00\x00\x03\x01\x01\x00\x18\x14\xdf\xcb\x00\x00\x00\x00IEND\xaeB`\x82',
    "yellow": b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xfb\xff\xff\x00\x06\xfe\x02\xfe\r\x9b\xa6\x8d\x00\x00\x00\x00IEND\xaeB`\x82'
}

def user_worker():
    while time.time() < END_TIME:
        req_id = "999999999999"
        u_id = str(uuid.uuid4())
        email = "dbdump500001@example.org"
        try:
            url = f"{target_url}/v1/user?email={email}&requestid={req_id}&uuid={u_id}"
            res = requests.get(url, timeout=3)
            with lock:
                if res.status_code == 200:
                    stats["user_success"] += 1
                else:
                    stats["user_fail"] += 1
        except Exception:
            with lock:
                stats["user_fail"] += 1
        time.sleep(0.05)

# 2. product API 워커 (Red, Blue, Yellow 이미지 랜덤 선택 후 업로드)[cite: 1]
def product_worker():
    while time.time() < END_TIME:
        req_id = "999999999999"
        u_id = str(uuid.uuid4())
        try:
            data = {
                "requestid": req_id,
                "uuid": u_id,
                "id": "dbdump500001"
            }
            color_name, img_bytes = random.choice(list(COLORED_IMAGES.items()))
            files = {
                'image': (f'product_{color_name}.png', img_bytes, 'image/png')
            }
            res = requests.put(f"{target_url}/v1/product", data=data, files=files, timeout=3)
            with lock:
                if res.status_code == 200:
                    stats["product_success"] += 1
                else:
                    stats["product_fail"] += 1
        except Exception:
            with lock:
                stats["product_fail"] += 1
        time.sleep(0.05)

# 3. stress API 워커[cite: 1]
def stress_worker():
    while time.time() < END_TIME:
        try:
            payload = {
                "requestid": "999999999999",
                "uuid": str(uuid.uuid4()),
                "length": 256
            }
            res = requests.post(f"{target_url}/v1/stress", json=payload, timeout=3)
            with lock:
                if res.status_code == 201:
                    stats["stress_success"] += 1
                else:
                    stats["stress_fail"] += 1
        except Exception:
            with lock:
                stats["stress_fail"] += 1
        time.sleep(0.05)

# 4. S3 이미지 다운로드 워커 (랜덤 색상의 이미지 경로 GET 요청)[cite: 1]
def image_download_worker():
    while time.time() < END_TIME:
        color_name = random.choice(["red", "blue", "yellow"])
        try:
            res = requests.get(f"{target_url}/images/product_{color_name}.png", timeout=3)
            with lock:
                if res.status_code == 200:
                    stats["image_success"] += 1
                else:
                    stats["image_fail"] += 1
        except Exception:
            with lock:
                stats["image_fail"] += 1
        time.sleep(0.05)

# 5. 악성 공격 워커[cite: 1]
def attack_worker():
    while time.time() < END_TIME:
        rand_word = random.choice(BAD_WORDS)
        headers = {"type": rand_word}
        try:
            res = requests.get(f"{target_url}/v1/product?id={rand_word}", headers=headers, timeout=3)
            with lock:
                if res.status_code == 403:
                    stats["attack_blocked"] += 1
                else:
                    stats["attack_missed"] += 1
        except Exception:
            with lock:
                stats["attack_missed"] += 1
        time.sleep(0.05)

threads = []
workers = [user_worker, product_worker, stress_worker, image_download_worker, attack_worker]

for worker_func in workers:
    for _ in range(8):
        t = threading.Thread(target=worker_func)
        t.daemon = True
        t.start()
        threads.append(t)

try:
    while time.time() < END_TIME:
        time.sleep(10)
        now = time.time()
        elapsed = int(now - START_TIME)
        remains = int(END_TIME - now)
        
        with lock:
            tot_user = stats["user_success"] + stats["user_fail"]
            tot_prod = stats["product_success"] + stats["product_fail"]
            tot_stress = stats["stress_success"] + stats["stress_fail"]
            tot_img = stats["image_success"] + stats["image_fail"]
            tot_atk = stats["attack_blocked"] + stats["attack_missed"]
            
            total_normal = tot_user + tot_prod + tot_stress + tot_img
            success_normal = stats["user_success"] + stats["product_success"] + stats["stress_success"] + stats["image_success"]
            
            avail_rate = (success_normal / total_normal * 100) if total_normal > 0 else 0
            sec_rate = (stats["attack_blocked"] / tot_atk * 100) if tot_atk > 0 else 0
            
            print(f"⏱️ [진행: {elapsed//60:02d}분 {elapsed%60:02d}초 | 남은시간: {remains//60:02d}분 {remains%60:02d}초]")
            print(f"   ▶ 누적: User {tot_user} | Product(PUT) {tot_prod} | Stress {tot_stress} | 이미지다운 {tot_img} | 공격 {tot_atk}")
            print(f"   ▶ 현황: 가동률 {avail_rate:.1f}% | 방어율 {sec_rate:.1f}%")
except KeyboardInterrupt:
    print("\n채점이 중단되었습니다.")

print("\n===================================================")
print("🏁 평가 종료! 공식 규격 기준 최종 결과를 집계합니다.")
print("===================================================")

tot_user = stats["user_success"] + stats["user_fail"]
tot_prod = stats["product_success"] + stats["product_fail"]
tot_stress = stats["stress_success"] + stats["stress_fail"]
tot_img = stats["image_success"] + stats["image_fail"]
tot_atk = stats["attack_blocked"] + stats["attack_missed"]

actual_normal = (tot_user + tot_prod + tot_stress + tot_img) if (tot_user + tot_prod + tot_stress + tot_img) > 0 else 1
actual_attack = tot_atk if tot_atk > 0 else 1

success_total = stats["user_success"] + stats["product_success"] + stats["stress_success"] + stats["image_success"]
fail_total = stats["user_fail"] + stats["product_fail"] + stats["stress_fail"] + stats["image_fail"]

availability_score = (success_total / actual_normal) * 50
security_score = (stats["attack_blocked"] / actual_attack) * 50
total_score = availability_score + security_score

print(f"정상 트래픽 처리 (User/Prod/Stress/S3) : {success_total} / {actual_normal} 건 (에러/지연: {fail_total}건)")
print(f"악성 트래픽 차단 (WAF 방어)           : {stats['attack_blocked']} / {actual_attack} 건 (방어 실패: {stats['attack_missed']}건)")
print("---------------------------------------------------")
print(f"가동률 점수 (50점 만점) : {availability_score:.1f} 점")
print(f"보안성 점수 (50점 만점) : {security_score:.1f} 점")
print("===================================================")
print(f"최종 획득 점수          : {total_score:.1f} / 100.0 점")
print("===================================================")