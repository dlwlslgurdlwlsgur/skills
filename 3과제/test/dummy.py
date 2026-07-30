import random
import string
import sys
import uuid

def generate_random_string(length=8):
    """랜덤 문자열 생성 함수"""
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for _ in range(length))

filename = "load_user.dump"
total_records = 10000
batch_size = 1000

print(f"🚀 {total_records}개의 더미 데이터를 포함한 {filename} 생성을 시작합니다...")

try:
    with open(filename, 'w', encoding='utf-8') as f:
        for i in range(0, total_records, batch_size):
            values = []
            for j in range(batch_size):
                # 1. id: VARCHAR(255) 스키마에 맞게 고유한 UUID 문자열 할당
                user_id = str(uuid.uuid4())
                
                # 2. username: VARCHAR(255) UNIQUE 조건에 맞게 생성
                username = f"user_{i+j+1}_{generate_random_string(4)}"
                
                # 3. email: VARCHAR(255) 
                email = f"test_{username}@example.com"
                
                values.append(f"('{user_id}', '{username}', '{email}')")
            
            # 첨부해주신 이미지의 정확한 컬럼명(id, username, email) 매칭
            insert_query = "INSERT INTO user (id, username, email) VALUES\n"
            insert_query += ",\n".join(values) + ";\n\n"
            f.write(insert_query)
            
            print(f"⏳ {i + batch_size}/{total_records} 건 생성 완료...")

    print(f"✅ 성공적으로 {filename} 파일이 생성되었습니다! (크기: 약 {total_records // 1000}MB 내외)")

except Exception as e:
    print(f"❌ 파일 생성 중 오류가 발생했습니다: {e}")
    sys.exit(1)