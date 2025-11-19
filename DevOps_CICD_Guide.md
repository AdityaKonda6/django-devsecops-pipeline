

# End-to-End CI/CD Pipeline: Django to AWS EC2 via GitHub Actions

This guide documents the complete setup of a DevOps pipeline that automates security scanning, container building (Docker), pushing to AWS ECR, and deploying to an AWS EC2 instance.

## 📋 Architecture Overview
1.  **Developer** pushes code to GitHub (`main` branch).
2.  **GitHub Actions** triggers the pipeline.
3.  **Security Job:** Runs **Bandit** (SAST) and **Trivy** (Container scan).
4.  **Build Job:** Builds Docker image and pushes to **AWS ECR**.
5.  **Deploy Job:** SSHs into **AWS EC2**, pulls the new image, and restarts the container.

---

## 🛠 Phase 1: AWS Setup (Infrastructure)

### 1. Create AWS ECR Repository
* Go to **AWS Console** -> **Elastic Container Registry (ECR)**.
* Create a **Private Repository**.
* Name: `my-django-app`.
* **Save the URI:** (e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com/my-django-app`).

### 2. Create IAM Role for EC2
* Go to **IAM** -> **Roles** -> **Create Role**.
* Trusted Entity: **EC2**.
* Permissions: Search and add `AmazonEC2ContainerRegistryReadOnly` `AmazonEC2ContainerRegistryPowerUser` `AmazonEC2ContainerRegistryFullAccess`.
* Name: `EC2-ECR-Pull-Role`.
* Also create a policy and Select JSON and paste below code on JSON
```bash
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
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "*"
        }
    ]
}
```

### 3. Launch EC2 Instance
* **OS:** Ubuntu 22.04 or 24.04.
* **Key Pair:** Create and download `.pem` file (e.g., `django-key.pem`).
* **Network Security Group:**
    * Allow SSH (Port 22).
    * Allow Custom TCP (Port 8000) - *For Django*.
* **Advanced Details (Crucial):** In "IAM Instance Profile", select `EC2-ECR-Pull-Role`.

### 4. Configure EC2 Server (Manual Steps)
SSH into your instance:
```bash
ssh -i "django-key.pem" ubuntu@<EC2_PUBLIC_IP>
````

Run the following commands inside EC2 to prepare it:

```bash
# 1. Update OS
sudo apt update

# 2. Install Docker
sudo apt install docker.io -y
sudo usermod -aG docker ubuntu

# 3. Install AWS CLI (Required for login command)
sudo apt install awscli -y

# 4. Verify Permissions
aws ecr get-login-password --region us-east-1
# (If this outputs a long token, permissions are correct)
```

-----

## 💻 Phase 2: Local Project Configuration

### 1\. Dockerfile

Ensure a `Dockerfile` exists (If your code is in a subfolder like `helloworld`, place it there).

```dockerfile
# Use a slim Python image
FROM python:3.11-slim

# Set environment
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Create app dir
WORKDIR /app

# Install system deps (for psycopg2) and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Copy dependency files first for caching
COPY requirements.txt /app/

# Install Python dependencies
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Copy application code
COPY . /app

# Collect static files (only necessary if DEBUG=False and you use static files)
ENV DJANGO_SETTINGS_MODULE=helloworld.settings
RUN python manage.py collectstatic --noinput || true

# Expose port (gunicorn will listen here)
EXPOSE 8000

# Entrypoint will run migrations and start server (see entrypoint.sh below)
COPY ./entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Default command
CMD ["/app/entrypoint.sh"]

```

### 2\. Requirements

Generate your requirements file:

```bash
Django>=4.2
gunicorn
psycopg2-binary
```
### 3\. Entrypoint.sh

```bash
#!/bin/bash

# Fail fast
set -e

# Optionally wait for DB (simple loop)
if [ "$DATABASE_URL" ]; then
  echo "Waiting for database..."
  # You could use dj-database-url + a wait script here. Keep simple:
  sleep 1
fi

# Run migrations
echo "Running migrations..."
python manage.py migrate --noinput

# Collect static if in production (DEBUG=False)
if [ "$DJANGO_COLLECTSTATIC" = "1" ]; then
  echo "Collecting static files..."
  python manage.py collectstatic --noinput
fi

# Start server with gunicorn
echo "Starting Gunicorn..."
exec gunicorn helloworld.wsgi:application \
  --bind 0.0.0.0:8000 \
  --workers 3 \
  --log-level info

```

### 4\. Docker-Compose.yml 

```bash
version: "3.9"
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_DB: hellodb
      POSTGRES_USER: hello
      POSTGRES_PASSWORD: hello123
    volumes:
      - db_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  web:
    build: .
    command: >
      sh -c "python manage.py migrate --noinput &&
             python manage.py runserver 0.0.0.0:8000"
    volumes:
      - .:/app
    ports:
      - "8000:8000"
    environment:
      - DEBUG=1
      - DATABASE_NAME=hellodb
      - DATABASE_USER=hello
      - DATABASE_PASSWORD=hello123
      - DATABASE_HOST=db
      - DATABASE_PORT=5432
    depends_on:
      - db

volumes:
  db_data:
```

-----

## 🔐 Phase 3: GitHub Secrets

Go to **Settings** -\> **Secrets and variables** -\> **Actions** -\> **New repository secret**. Add these:

| Secret Name | Description |
| :--- | :--- |
| `AWS_ACCESS_KEY_ID` | Go to your AWS account overview
||Account menu in the upper-right (has your name on it)
||sub-menu: Security Credentials |
| `AWS_SECRET_ACCESS_KEY` | Your IAM User Secret Key |
||Sign in to the AWS Management Console and navigate to the IAM console.
||Click on your profile name in the top right corner and select "My Security Credentials".
||Scroll to the "Access Keys" section and click "Create new access key".|
| `AWS_REGION` | `us-east-1` |
| `AWS_ECR_REPO_URI` | The URI copied from ECR (without tags) |
| `EC2_HOST` | Public IP of the EC2 instance
||Public IPv4 address
||13.233.151.*** |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | The entire content of your `.pem` file |

-----

## 🚀 Phase 4: The Pipeline (`.github/workflows/main.yml`)

Create this file in your repository.

```yaml
name: Django CI/CD Pipeline

on:
  push:
    branches: [ "main" ]

jobs:
  # JOB 1: Security Checks
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

      - name: Run Bandit Security Check
        # EXCLUDES venv folder to prevent false positives
        run: bandit -lll -r . -x ./venv,./tests

      - name: Run Trivy Vulnerability Scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
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
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: ${{ secrets.AWS_ECR_REPO_URI }}
          IMAGE_TAG: latest
        run: |
          # Note: Pointing to ./helloworld folder where Dockerfile is located
          docker build -t $ECR_REPOSITORY:$IMAGE_TAG ./helloworld
          docker push $ECR_REPOSITORY:$IMAGE_TAG

  # JOB 3: Deploy to EC2
  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to EC2 via SSH
        uses: appleboy/ssh-action@v0.1.6
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          port: 22
          script: |
            # Login to ECR using installed AWS CLI
            aws ecr get-login-password --region ${{ secrets.AWS_REGION }} | docker login --username AWS --password-stdin ${{ secrets.AWS_ECR_REPO_URI }}
            
            # Pull and Run
            docker pull ${{ secrets.AWS_ECR_REPO_URI }}:latest
            docker stop django-app || true
            docker rm django-app || true
            docker run -d -p 8000:8000 --name django-app ${{ secrets.AWS_ECR_REPO_URI }}:latest
```

-----

## ⚠️ Common Mistakes & Solutions (Troubleshooting Log)

During the creation of this project, we encountered and solved the following specific errors:

### 1\. Git Authentication Error

  * **Error:** `Password authentication is not supported for Git operations.`
  * **Cause:** GitHub removed password support for CLI.
  * **Solution:** Generated a **Personal Access Token (PAT)** in GitHub Settings -\> Developer Settings and used it as the password.

### 2\. Branch Name Mismatch

  * **Error:** `error: src refspec main does not match any`
  * **Cause:** Local branch was named `master`, but remote expected `main`.
  * **Solution:** Renamed local branch: `git branch -m main`.

### 3\. Bandit Security Scan Failed

  * **Error:** Bandit scanned thousands of files and crashed.
  * **Cause:** Bandit was scanning the virtual environment (`venv`) folder which contains third-party library code.
  * **Solution:** Updated command to exclude that folder: `bandit -lll -r . -x ./venv`.

### 4\. Docker Build Failed

  * **Error:** `failed to read dockerfile: open Dockerfile: no such file or directory`
  * **Cause:** The `Dockerfile` was inside a subfolder (`helloworld/`), but the pipeline was looking in the root (`.`).
  * **Solution:** Updated the build command path: `docker build ... ./helloworld`.

### 5\. EC2 Deployment Failed

  * **Error:** `bash: line 2: aws: command not found`
  * **Cause:** The AWS CLI tool was not installed on the Ubuntu EC2 instance.
  * **Solution:** SSH'd into the server and ran `sudo apt install awscli`.

---
---
### Since AWS charges for running resources (EC2) and storage (ECR), deleting them is a smart move when you are not practicing.

However, when you come back to run it again, **just updating the Secrets is not enough.** You also have to redo the **manual setup inside the new EC2**.

Here is your **"Restart Checklist"** for when you come back next time:

### 1\. What You Must Create in AWS

1.  **Create ECR:** Create the repository again (e.g., `my-django-app`).
2.  **Create EC2:** Launch a new Ubuntu instance.
      * **Important:** Don't forget to select the **IAM Role** (`EC2-ECR-Pull-Role`) in the "Advanced Details" section.
      * **Security Group:** Open Port **8000** and **22**.

-----

### 2\. Secrets You Must Update in GitHub

Go to **Settings $\rightarrow$ Secrets** and update these 3 values (the others usually stay the same):

| Secret Name | Status | Action |
| :--- | :--- | :--- |
| `EC2_HOST` | **Changed** | Update with the **new** Public IP of the new EC2. |
| `AWS_ECR_REPO_URI` | **Changed** | Update with the **new** URI (even if the name is the same, it's good to check). |
| `EC2_SSH_KEY` | **Changed** | If you created a **new** Key Pair, update this. (If you reused the old `.pem` file, you don't need to change this). |

*Note: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` do **not** need to change unless you deleted the IAM User.*

-----

### 3\. The Step You Might Forget (Crucial\!) ⚠️

Because the new EC2 is "fresh," it is empty. It does not have Docker or the AWS CLI installed. The pipeline will fail if you don't do this.

**You must SSH into the new EC2 and run these commands once:**

```bash
# 1. Login
ssh -i "your-key.pem" ubuntu@<NEW_PUBLIC_IP>

# 2. Install Docker & AWS CLI again
sudo apt update
sudo apt install docker.io awscli -y
sudo usermod -aG docker ubuntu

# 3. Check if the IAM Role works
aws ecr get-login-password --region us-east-1
```

### Summary

So the formula for next time is:

1.  Create AWS Resources (EC2 + ECR).
2.  **Configure EC2 (Install Docker/AWS CLI).** \<--- *Don't skip this\!*
3.  Update GitHub Secrets.
4.  Push a change to GitHub.

Enjoy your break from the costs\! You've done great work today.

---

This file is a **GitHub Actions workflow** written in YAML. It defines a complete, multi-stage **Continuous Integration/Continuous Deployment (CI/CD)** pipeline with integrated **DevSecOps** (Security) checks for your Django application.

Think of it as an automated assembly line for your code: every time you push changes, the code is tested, scanned, packaged, and delivered.

-----

## ⚙️ How the CI/CD Pipeline Works

The workflow is structured into **four independent jobs** that execute sequentially, as each subsequent job depends on the successful completion of the previous one.

### 1\. The Trigger (`on`)

The pipeline starts whenever code is pushed to or a pull request is made against the **`main`** branch.

```yaml
on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]
```

-----

## 2\. Job 1: `security-check` (Code Security)

This is the **Continuous Integration (CI)** stage that focuses on the security of the source code before any packaging begins. If this job fails, the entire pipeline stops.

| Step | Action | Purpose |
| :--- | :--- | :--- |
| **Bandit Check** | `pip install bandit` then `bandit -lll -r . -x ./venv` | Runs **Static Analysis Security Testing (SAST)**. Bandit scans your Python code for common security issues (like using insecure functions or hardcoded passwords). The `-x ./venv` flag ensures the virtual environment files are ignored. |
| **Trivy (FS Mode)** | `uses: aquasecurity/trivy-action@master` with `scan-type: 'fs'` | Scans the local filesystem (**FS Mode**). It specifically checks the `requirements.txt` file (located in `./helloworld`) for **dependency vulnerabilities** and also scans all files for **hardcoded secrets**. |

-----

## 3\. Job 2: `build-and-push` (Containerization)

This job only runs if the `security-check` job **passes** (`needs: security-check`). It handles containerization and storage in the cloud.

| Step | Action | Purpose |
| :--- | :--- | :--- |
| **AWS Login** | `uses: aws-actions/configure-aws-credentials` | Uses your GitHub Secrets (`AWS_ACCESS_KEY_ID`, etc.) to authenticate the runner with AWS. |
| **ECR Login** | `uses: aws-actions/amazon-ecr-login@v1` | Authenticates the Docker client with **Elastic Container Registry (ECR)** so it can push the image. |
| **Build & Push**| `docker build...` then `docker push...` | Builds the **Docker image** using the `Dockerfile` in the `./helloworld` directory and pushes the tagged image (`:latest`) to your ECR repository. |

-----

## 4\. Job 3: `trivy-scan-image` (Image Security Gate)

This is a critical security step that runs **after** the image is built, but **before** it is deployed.

| Step | Action | Purpose |
| :--- | :--- | :--- |
| **Image Scan** | `uses: aquasecurity/trivy-action@master` with `scan-type: 'image'` | Pulls the newly pushed image from ECR and performs a deep scan of the **entire container layer stack**. It checks for: **OS vulnerabilities** (e.g., outdated Debian packages) and **Misconfigurations** (e.g., running the container as the root user). |
| **Exit Code** | `exit-code: '1'` with `severity: 'CRITICAL,HIGH'` | If Trivy finds any **Critical** or **High** severity issues in the image, the job **fails**, preventing the deployment of the vulnerable container. |

-----

## 5\. Job 4: `deploy` (Continuous Deployment)

This job only runs if the `trivy-scan-image` job **passes** (`needs: trivy-scan-image`). This ensures a clean, secure image is deployed.

| Step | Action | Purpose |
| :--- | :--- | :--- |
| **SSH Deploy** | `uses: appleboy/ssh-action@v0.1.6` | Uses the SSH secret key to connect securely to your **AWS EC2** instance. |
| **Script Execution**| `script: | ...` | Executes a shell script directly on the EC2 machine: |
| | **1. `aws ecr get-login-password...`** | Logs the EC2 server's Docker client into ECR (using the EC2's IAM Role). |
| | **2. `docker pull...`** | Downloads the newly scanned, clean image from ECR. |
| | **3. `docker stop/rm...`** | Stops and deletes the currently running old container. |
| | **4. `docker run -d -p 8000:8000...`**| Starts the new container with the updated code, mapping port 8000 to the host. |

-----

## 🔄 What Was Corrected with Trivy

The first version of the workflow had an issue where the initial Trivy scan in the `security-check` job was not effective:

| Previous Trivy (Ineffective) | Current Trivy (Corrected) | Why the change was needed |
| :--- | :--- | :--- |
| **Command:** `trivy fs .` | **Command:** `trivy fs ./helloworld` | The **`requirements.txt`** file was often missed because it wasn't in the root (`.`). The fix explicitly points the file system scanner to the subdirectory where the dependencies live. |
| **Missing Job:** No subsequent image scan. | **Added Job:** `trivy-scan-image` (Job 3). | Scanning the *code* (`fs`) doesn't catch issues in the **base image** (e.g., the underlying Debian OS). The new job runs a comprehensive **image scan** (`scan-type: 'image'`) to check for vulnerabilities and misconfigurations in the final package. |

The pipeline now utilizes a true **DevSecOps** pattern by scanning the code, then the dependencies, and finally the built artifact (the Docker image) **before** deployment.

---

Use this command for temporary going to that container instead of exec -it
docker run --rm -it 534232118663.dkr.ecr.ap-south-1.amazonaws.com/mydjango:latest sh
