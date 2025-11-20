This is a comprehensive guide to your CI/CD pipeline\! To integrate the Nginx and DevSecOps best practices we've implemented, I'll update the guide by focusing on the **Docker-Compose setup**, the **GitHub Actions workflow**, and making the documentation cleaner and more detailed.

I will also update the `Deploy` job in the workflow to use **Docker Compose**, which is how you run your `web`, `db`, and `nginx` services together, instead of the single `docker run` command.

-----

# 🚀 End-to-End DevSecOps CI/CD Pipeline: Django, Nginx & PostgreSQL on AWS EC2 via GitHub Actions

This guide documents the complete setup of a robust DevOps pipeline that automates security scanning, container building, pushing to AWS ECR, and deploying a multi-container (Django, Nginx, DB) application to an AWS EC2 instance using **Docker Compose**.

## 📋 Architecture Overview

1.  **Developer** pushes code to GitHub (`main` branch).
2.  **GitHub Actions** triggers the pipeline.
3.  **Security Job:** Runs **Bandit** (SAST) and **Trivy** (Code/Dependency scan).
4.  **Build Job:** Builds Docker image and pushes to **AWS ECR**.
5.  **Image Scan Job:** Runs **Trivy** on the **built image** to ensure security compliance.
6.  **Deploy Job:** SSHs into **AWS EC2**, copies deployment files (including **Nginx config**), pulls the new image, and executes **`docker compose up -d`** to restart the stack.

-----

## 🛠 Phase 1: AWS Setup (Infrastructure)

### 1\. Create AWS ECR Repository

  * Go to **AWS Console** $\rightarrow$ **Elastic Container Registry (ECR)**.
  * Create a **Private Repository**.
  * Name: `my-django-app`.
  * **Save the URI:** (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-django-app`).

### 2\. Create IAM Role for EC2 (ECR Access)

This role grants the EC2 instance permission to pull images from ECR.

  * Go to **IAM** $\rightarrow$ **Roles** $\rightarrow$ **Create Role**.
  * Trusted Entity: **EC2**.
  * **Attach Policies:**
      * `AmazonEC2ContainerRegistryReadOnly`
  * **Create Custom Policy (for push access via the runner):** Select JSON and paste the code below:
    ```json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ecr:GetAuthorizationToken",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:PutImage",
                    "ecr:CreateRepository",
                    "ecr:DescribeRepositories",
                    "ecr:GetRepositoryPolicy",
                    "ecr:ListImages",
                    "ecr:BatchGetImage",
                    "ecr:DeleteRepository",
                    "ecr:BatchDeleteImage"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": ["s3:GetObject"],
                "Resource": "*"
            }
        ]
    }
    ```
  * Name the combined role: `EC2-ECR-Pull-Role`.

### 3\. Launch EC2 Instance

  * **OS:** Ubuntu 22.04 or 24.04.
  * **Key Pair:** Create and download the `.pem` file (e.g., `django-key.pem`).
  * **Network Security Group (Crucial):**
      * Allow SSH (Port 22).
      * Allow HTTP (Port **80**) - **Required for Nginx.**
      * *Port 8000 is not needed externally, as Nginx handles access.*
  * **Advanced Details (Crucial):** In "IAM Instance Profile", select `EC2-ECR-Pull-Role`.

### 4\. Configure EC2 Server (Manual Setup)

SSH into your instance once to install prerequisites:

```bash
ssh -i "django-key.pem" ubuntu@<EC2_PUBLIC_IP>
```

Run the following commands:

```bash
# 1. Update OS and Install Prerequisites
sudo apt update
sudo apt install docker.io awscli netcat -y
sudo usermod -aG docker ubuntu

# 2. Install Docker Compose (for production stack deployment)
# Determine the latest version here: https://github.com/docker/compose/releases
DOCKER_COMPOSE_VERSION="v2.24.5"
sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
docker-compose --version

# 3. Create Deployment Directory
mkdir -p ~/django-app-deploy/helloworld

# 4. Verify Permissions
# (If this outputs a long token, the IAM role is correctly applied)
aws ecr get-login-password --region us-east-1
```

-----

## 💻 Phase 2: Local Project Configuration (Multi-Service Setup)

### 1\. Project Structure

Ensure you have the following files in your **`helloworld`** subdirectory:

```
my-repo/
└── helloworld/
    ├── Dockerfile
    ├── requirements.txt
    ├── entrypoint.sh
    ├── docker-compose.yml  <-- Updated to use Nginx
    └── nginx/              <-- NEW Directory
        ├── nginx.conf      <-- Nginx configuration
        └── docker-entrypoint.sh <-- Nginx startup wait script
```

### 2\. Dockerfile, Requirements, and `entrypoint.sh`

The contents of these files remain as you provided. The `entrypoint.sh` runs migrations and starts Gunicorn on port **8000**.

### 3\. Nginx Configuration (`helloworld/nginx/nginx.conf`)

This configuration routes all public traffic (port 80) to the internal Django service (`web:8000`).

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

### 4\. Nginx Entrypoint Script (`helloworld/nginx/docker-entrypoint.sh`)

This script prevents the Nginx container from starting until the Django `web` container is fully up and listening on port 8000, preventing the **`host not found in upstream "web"`** error.

```bash
#!/bin/sh
set -e

# Wait for the web container (web:8000) to be available
echo "Waiting for Django web service..."
while ! nc -z web 8000; do
  sleep 0.5
done
echo "Django service ready! Starting Nginx."

# Execute the default Nginx entrypoint command
exec nginx -g "daemon off;"
```

### 5\. Docker-Compose (`helloworld/docker-compose.yml`)

This file defines the three services and links them.

**Replace the entire contents of your `helloworld/docker-compose.yml`:**

```yaml
services:
  db:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_DB: hellodb
      POSTGRES_USER: hello
      POSTGRES_PASSWORD: hello123
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hello -d hellodb"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s

  web:
    # IMPORTANT: The pipeline will replace 'build: .' with the ECR image URI
    build: . 
    command: /app/entrypoint.sh
    # Volumes and ports removed, as they are not needed for production deployment
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
      # Nginx exposes HTTP on port 80
      - "80:80" 
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/docker-entrypoint.sh:/docker-entrypoint.sh 
    entrypoint: ["/bin/sh", "/docker-entrypoint.sh"] 
    depends_on:
      - web

volumes:
  db_data:
```

-----

## 🔐 Phase 3: GitHub Secrets

Ensure all these secrets are configured in your repository settings:

| Secret Name | Description |
| :--- | :--- |
| `AWS_ACCESS_KEY_ID` | Your IAM User Access Key |
| `AWS_SECRET_ACCESS_KEY` | Your IAM User Secret Key |
| `AWS_REGION` | e.g., `us-east-1` |
| `AWS_ECR_REPO_URI` | Full ECR URI (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-django-app`) |
| `EC2_HOST` | Public IP of the EC2 instance (e.g., `13.233.151.***`) |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | The entire content of your `.pem` file |

-----

## 🚀 Phase 4: The Pipeline (`.github/workflows/main.yml`)

The pipeline is updated to use **Docker Compose** for deployment and includes the new file copies.

```yaml
name: Django CI/CD Pipeline

on:
  push:
    branches: [ "main" ]

jobs:
  # JOB 1: Code and Dependency Security Checks
  security-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'

      - name: Install Bandit
        run: pip install bandit

      - name: Run Bandit (SAST)
        run: bandit -lll -r ./helloworld -x ./venv,./tests 

      - name: Run Trivy (FS/Dependencies)
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: './helloworld' # Scan the project directory
          format: 'table'
          exit-code: '1'
          severity: 'CRITICAL,HIGH'

  # JOB 2: Build and Push to ECR
  build-and-push:
    needs: security-check
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build, tag, and push image
        env:
          ECR_REPOSITORY: ${{ secrets.AWS_ECR_REPO_URI }}
          IMAGE_TAG: latest
        run: |
          docker build -t $ECR_REPOSITORY:$IMAGE_TAG ./helloworld
          docker push $ECR_REPOSITORY:$IMAGE_TAG

  # JOB 3: Image Security Gate
  trivy-scan-image:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Run Trivy (Image Scan)
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ secrets.AWS_ECR_REPO_URI }}:latest
          scan-type: 'image'
          format: 'table'
          exit-code: '1'
          severity: 'CRITICAL,HIGH'
          
  # JOB 4: Deploy to EC2 via Docker Compose
  deploy:
    needs: trivy-scan-image
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Copy deployment files to EC2
        uses: appleboy/scp-action@v0.1.4
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          port: 22
          # 💡 NEW: Copy the docker-compose.yml AND the nginx directory to the target path
          source: "helloworld/docker-compose.yml,helloworld/nginx" 
          target: "/home/${{ secrets.EC2_USER }}/django-app-deploy/helloworld"
          
      - name: Deploy to EC2 via SSH
        uses: appleboy/ssh-action@v0.1.6
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          port: 22
          script: |
            # 1. Navigate to the deployment folder
            cd /home/${{ secrets.EC2_USER }}/django-app-deploy/helloworld
            
            # 2. Login to ECR (using the EC2's IAM Role)
            aws ecr get-login-password --region ${{ secrets.AWS_REGION }} | docker login --username AWS --password-stdin ${{ secrets.AWS_ECR_REPO_URI }}

            # 3. Pull the latest image (using the correct tag format)
            docker pull ${{ secrets.AWS_ECR_REPO_URI }}:latest
            
            # 4. Replace the 'build: .' line with the ECR image URI in the compose file
            # This allows the compose file to be used for deployment
            sed -i "s|build: .|image: ${{ secrets.AWS_ECR_REPO_URI }}:latest|g" docker-compose.yml

            # 5. Stop and remove the old stack, then start the new stack
            docker compose down -v || true
            docker compose up -d
```

-----

## ⚠️ Common Mistakes & Solutions (Troubleshooting Log)

| Error Encountered | Cause | Solution |
| :--- | :--- | :--- |
| `Password authentication is not supported for Git operations.` | GitHub removed password support for CLI. | Generated a **Personal Access Token (PAT)** in GitHub and used it as the password/token. |
| `error: src refspec main does not match any` | Local branch (`master`) name didn't match remote (`main`). | Renamed local branch: `git branch -m main`. |
| Bandit scanned thousands of files and crashed. | Bandit scanned the virtual environment (`venv`) folder. | Updated command to exclude that folder: `bandit -lll -r . -x ./venv`. |
| `failed to read dockerfile: open Dockerfile: no such file or directory` | `Dockerfile` was inside `./helloworld/` but build command pointed to `.`. | Updated build path: `docker build ... ./helloworld`. |
| `bash: aws: command not found` | AWS CLI was not installed on the Ubuntu EC2 instance. | SSH'd into the server and ran `sudo apt install awscli`. |
| `failed to bind host port 0.0.0.0:80/tcp: address already in use` | A residual **Nginx service was running on the EC2 host**. | Stopped and disabled the host service: `sudo systemctl stop nginx` & `sudo systemctl disable nginx`. |
| `host not found in upstream "web"` | Nginx container started before the Django `web` container was ready. | **Solved** by adding `nginx/docker-entrypoint.sh` to force a wait for `web:8000`. |
| **Missing dependency scans** | The original Trivy only scanned the root directory. | Added explicit image scan (`trivy-scan-image`) and pointed the file system scan to `./helloworld` to catch dependencies. |

-----

## ♻️ Restart Checklist: Restoring a Deleted Environment

If you delete your AWS resources to save costs, here is the process to get back up and running:

### 1\. What You Must Create in AWS

1.  **Create ECR:** Create the repository again (`my-django-app`).
2.  **Create EC2:** Launch a new Ubuntu instance.
      * **Crucial:** Select the **IAM Role** (`EC2-ECR-Pull-Role`).
      * **Security Group:** Open Port **80** (HTTP) and **22** (SSH).

### 2\. Secrets You Must Update in GitHub

| Secret Name | Status | Action |
| :--- | :--- | :--- |
| `EC2_HOST` | **MUST CHANGE** | Update with the **new** Public IP of the new EC2. |
| `AWS_ECR_REPO_URI` | **Check** | Update with the **new** ECR URI. |
| `EC2_SSH_KEY` | **Check** | If you generated a **new** Key Pair, update this. |

### 3\. Manual EC2 Configuration (The Step Often Forgotten\! ⚠️)

The new EC2 instance is bare. You **must** SSH in and prepare it for Docker deployment:

```bash
# 1. Login
ssh -i "your-key.pem" ubuntu@<NEW_PUBLIC_IP>

# 2. Install Docker, AWS CLI, Netcat, and Docker Compose
sudo apt update
sudo apt install docker.io awscli netcat -y
sudo usermod -aG docker ubuntu

# 3. Install Docker Compose
DOCKER_COMPOSE_VERSION="v2.24.5" 
sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 4. Verify IAM Role
aws ecr get-login-password --region us-east-1
```

Once this is complete, pushing a change to GitHub will trigger the automated deployment\!
