import sys
import uuid

filename = "load_user.dump"
total_records = 30000
batch_size = 1000

print(f"🚀 {total_records}개의 전국대회 규격 타겟 데이터(dbdump00001~30000)를 포함한 {filename} 생성을 시작합니다...")

try:
    with open(filename, 'w', encoding='utf-8') as f:
        for i in range(0, total_records, batch_size):
            values = []
            for j in range(1, batch_size + 1):
                current_num = i + j
                
                # 1. 고유한 UUID 할당
                user_id = str(uuid.uuid4())
                
                # 2. 채점 봇이 정확히 타겟팅할 username (dbdump00001 ~ dbdump30000)
                username = f"dbdump{current_num:05d}"
                
                # 3. 채점 봇이 조회할 정확한 email
                email = f"{username}@example.org"
                
                values.append(f"('{user_id}', '{username}', '{email}')")
            
            # 쿼리 조립 및 파일 쓰기
            insert_query = "INSERT INTO user (id, username, email) VALUES\n"
            insert_query += ",\n".join(values) + ";\n\n"
            f.write(insert_query)
            
            print(f"⏳ {i + batch_size}/{total_records} 건 생성 완료...")

    print(f"✅ 성공적으로 {filename} 파일이 생성되었습니다! (크기: 약 {total_records // 1000}MB 내외)")

except Exception as e:
    print(f"❌ 파일 생성 중 오류가 발생했습니다: {e}")
    sys.exit(1)