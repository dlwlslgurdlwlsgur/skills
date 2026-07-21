def calculate_grade(average):
    if average >= 90:
        return "A"
    elif average >= 80:
        return "B"
    elif average >= 70:
        return "C"
    elif average >= 60:
        return "D"
    else:
        return "F"


def save_student(table, row):
    korean = int(row["korean"].strip())
    english = int(row["english"].strip())
    math = int(row["math"].strip())
    science = int(row["science"].strip())
    history = int(row["history"].strip())
    
    total_score = korean + english + math + science + history
    average = round(total_score / 5, 2)
    
    grade = calculate_grade(average)
    
    created_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    item = {
        "studentId": row["studentId"].strip(),
        "examDate": row["examDate"].strip(),
        "name": row["name"].strip(),
        "className": row["className"].strip(),
        "korean": korean,
        "english": english,
        "math": math,
        "science": science,
        "history": history,
        "average": Decimal(str(average)),
        "grade": grade,
        "createdAt": created_at
    }
    
    table.put_item(Item=item)