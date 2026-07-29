## shell
- 01-vpc.sh
- 02-ec2.sh

<br>

## EC2
- 03-cluster.sh
- 04-rds.sh
- 05-s3.sh
- 06-ecr.sh

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