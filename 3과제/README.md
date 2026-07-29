## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/01-vpc.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/02-ec2.sh
```

<br>

## shell
- ec2 접속
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/03-cluster.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/04-rds.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/05-s3.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/06-ecr.sh
```

<br>

## RDS
```bash
CREATE TABLE IF NOT EXISTS user (
  id       VARCHAR(255) NOT NULL,
  username VARCHAR(255) NOT NULL,
  email    VARCHAR(255) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_username (username)
);

CREATE TABLE IF NOT EXISTS product (
  id         VARCHAR(255) NOT NULL,
  name       VARCHAR(255) NOT NULL,
  price      FLOAT(8) NOT NULL,
  image_path VARCHAR(500) DEFAULT NULL,
  PRIMARY KEY (id)
);

CREATE INDEX idx_user_email_cover ON user (email, username);
```

<br>

## shell
```bash
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/07-manifest.sh
wget https://raw.githubusercontent.com/wngnlwngnl/skills/refs/heads/main/3%EA%B3%BC%EC%A0%9C/08-monitoring.sh
```