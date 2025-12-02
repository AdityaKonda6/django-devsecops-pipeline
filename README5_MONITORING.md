Sure! Below is a **clean, well-structured deployment guide in Markdown (`deploy_ec2_docker_prom_stack.md`)** that includes:

✅ Creating IAM user
✅ Creating EC2 instance
✅ Attaching IAM role
✅ Creating ECR repo
✅ Building & pushing Docker image
✅ Installing Docker & AWS CLI on EC2
✅ Cloning your project + adding monitoring stack
✅ Running `docker compose up -d`
✅ Opening security group ports
✅ Verifying logs

You can copy/paste this into a file named:

```
deploy_ec2_docker_prom_stack.md
```

---

# 🚀 **Full Deployment Guide: EC2 + Docker + ECR + Prometheus/Grafana + cAdvisor + NGINX**

## 📌 **1. Create IAM User for ECR**

1. Go to **AWS Console → IAM → Users → Create User**
2. Name: `ecr-user`
3. Attach policy:

   * **AmazonEC2ContainerRegistryFullAccess**
4. Download **Access Key + Secret Key**

---

## 📌 **2. Create IAM Role for EC2**

1. Go to **IAM → Roles → Create role**
2. Trusted entity: **EC2**
3. Attach policies:

   * `AmazonEC2ContainerRegistryReadOnly`
   * `CloudWatchAgentServerPolicy` (optional)
4. Name it: `EC2-ECR-ReadRole`

You will attach this role to your EC2 instance.

---

## 📌 **3. Create an EC2 Instance**

1. Go to **EC2 → Launch Instance**
2. Choose OS → **Ubuntu 22.04**
3. Instance type → `t2.micro`
4. Storage → 20GB (recommended when using Prometheus/Grafana)
5. Attach IAM role → `EC2-ECR-ReadRole`
6. Security group (open these ports):

| Port | Service      |
| ---- | ------------ |
| 22   | SSH          |
| 80   | Nginx / App  |
| 3000 | Grafana      |
| 9090 | Prometheus   |
| 9093 | AlertManager |
| 8080 | cAdvisor     |

7. Launch instance and download `.pem` key.

---

## 📌 **4. SSH into EC2**

```bash
ssh -i your-key.pem ubuntu@EC2_PUBLIC_IP
```

---

# 🐳 **5. Install Docker + Docker Compose + AWS CLI**

Run the following on EC2:

```bash
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```

Re-login to apply Docker group permissions:

```bash
exit
ssh -i your-key.pem ubuntu@EC2_PUBLIC_IP
```

### Install AWS CLI

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip
unzip awscliv2.zip
sudo ./aws/install
aws configure
```

Enter IAM user access key + region (`ap-south-1`).

---

# 🐳 **6. Create ECR Repository**

Run locally or in CloudShell:

```bash
aws ecr create-repository --repository-name helloworld-monitor-ecr --region ap-south-1
```

Copy the repo URI from output:

```
534232118663.dkr.ecr.ap-south-1.amazonaws.com/helloworld-monitor-ecr
```

---

# 🐳 **7. Build & Push Docker Image to ECR**

### Authenticate:

```bash
aws ecr get-login-password --region ap-south-1 \
| docker login --username AWS --password-stdin 534232118663.dkr.ecr.ap-south-1.amazonaws.com
```

### Build:

```bash
docker build -t helloworld-monitor-ecr .
```

### Tag:

```bash
docker tag helloworld-monitor-ecr:latest 534232118663.dkr.ecr.ap-south-1.amazonaws.com/helloworld-monitor-ecr:latest
```

### Push:

```bash
docker push 534232118663.dkr.ecr.ap-south-1.amazonaws.com/helloworld-monitor-ecr:latest
```

---

# 📁 **8. SSH Into EC2 and Prepare App Directory**

```bash
mkdir ~/app && cd ~/app
```

### Clone your main GitHub project:

```bash
git clone https://github.com/your/repo.git
```

(Your main Django project is separate; this guide only deploys the stack.)

---

# 📁 **9. Add Monitoring Stack Files to EC2**

### Create folder structure:

```bash
mkdir -p nginx alertmanager prometheus
```

---

## ✅ **Create `nginx/nginx.conf`**

```bash
nano nginx/nginx.conf
```

Paste:

```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://web:8000;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

## ✅ **Create `alertmanager/config.yml`**

```bash
nano alertmanager/config.yml
```

Paste:

```yaml
global:
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'janyakon31@gmail.com'
  smtp_auth_username: 'janyakon31@gmail.com'
  smtp_auth_password: 'QWRpdHlhQDI='

route:
  receiver: 'default-receiver'

receivers:
  - name: 'default-receiver'
    email_configs:
      - to: 'janyakon31@gmail.com'
```

---

## ✅ **Create `prometheus/prometheus.yml`**

```bash
nano prometheus/prometheus.yml
```

Paste:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - 'alerts.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'web_app'
    static_configs:
      - targets: ['web:8000']
```

---

# 📌 **10. Create `docker-compose.yml`**

```bash
nano docker-compose.yml
```

Paste the full compose you provided:

```yaml
version: "3.9"

services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: hellodb
      POSTGRES_USER: hello
      POSTGRES_PASSWORD: hello123
    volumes:
      - postgres_data:/var/lib/postgresql/data/
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hello -d hellodb"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s

  web:
    image: 534232118663.dkr.ecr.ap-south-1.amazonaws.com/helloworld-monitor-ecr:latest
    command: >
      sh -c "
      python manage.py migrate --noinput &&
      gunicorn helloworld.wsgi:application --bind 0.0.0.0:8000
      "
    environment:
      - DEBUG=1
      - DATABASE_NAME=hellodb
      - DATABASE_USER=hello
      - DATABASE_PASSWORD=hello123
      - DATABASE_HOST=db
      - DATABASE_PORT=5432
    depends_on:
      db:
        condition: service_healthy

  nginx:
    image: nginx:stable-alpine
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - web

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    privileged: true
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro

  prometheus:
    image: prom/prometheus:latest
    restart: always
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    depends_on:
      - cadvisor
      - web
      - alertmanager

  alertmanager:
    image: prom/alertmanager:latest
    restart: always
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/config.yml:/etc/alertmanager/config.yml:ro

  grafana:
    image: grafana/grafana:latest
    restart: always
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    depends_on:
      - prometheus

volumes:
  postgres_data:
  prometheus_data:
  grafana_data:
```
---

./prometheus/alerts.yml

```yaml
groups:
  - name: instance-down
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.job }} ({{ $labels.instance }}) is down"
          description: "Prometheus target {{ $labels.job }} ({{ $labels.instance }}) has been down for more than 1 minute."
```
---

# 🚀 **11. Start Everything**

```bash
docker compose pull
docker compose up -d
```

---

# 🧪 **12. Verify Logs**

```bash
docker compose logs -f web
docker compose logs -f prometheus
docker compose logs -f grafana
docker compose logs -f cadvisor
```

---

# 🌍 **13. Access Services**

| Service      | URL                                                    |
| ------------ | ------------------------------------------------------ |
| Django/Nginx | `http://EC2_PUBLIC_IP`                                 |
| cAdvisor     | `http://EC2_PUBLIC_IP:8080`                            |
| Prometheus   | `http://EC2_PUBLIC_IP:9090`                            |
| AlertManager | `http://EC2_PUBLIC_IP:9093`                            |
| Grafana      | `http://EC2_PUBLIC_IP:3000`  (user/pass = admin/admin) |

---

# 🎉 Deployment Complete!

If you want, I can also generate:

✅ A separate `README.md`
✅ A diagram of the architecture
✅ A bash script to automate the entire installation
✅ A Terraform version of this deployment

Just tell me!
