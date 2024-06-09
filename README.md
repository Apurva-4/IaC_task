# CI/CD Pipeline for Hello World Node.js App

This repository contains a CI/CD pipeline for deploying a Hello World Node.js application using AWS ECS/Fargate and GitHub Actions.

## Table of Contents
- Project Overview
- Architecture
- Prerequisites
- Setup
- Usage
- Workflow Explanation

## Project Overview
This project demonstrates how to set up a continuous integration and continuous deployment (CI/CD) pipeline for a Node.js application using GitHub Actions and AWS services including Amazon ECR and Amazon ECS/Fargate.

## Architecture
- **Node.js Application**: A simple Hello World application.
- **Amazon ECR**: Used to store Docker images.
- **Amazon ECS/Fargate**: Used to run the Docker containers.
- **GitHub Actions**: Used for CI/CD pipeline.
- **Terraform**: used to create AWS infrastructure VPC,subnet, network gateways,ECS etc

## Prerequisites
- AWS Account
- AWS CLI configured with appropriate IAM permissions
- GitHub repository with the source code of your Node.js application
- Docker installed locally for testing purposes
- Terraform installed locally

## Setup
1. **AWS Setup**:
   - Create an ECR repository named `hello-world`.
   - Create an ECS cluster named `hello-world-cluster`.
   - Create an ECS service named `hello-world-service` within the cluster.

2. **GitHub Setup**:
   - Add the following secrets to your GitHub repository:
     - `AWS_ACCESS_KEY_ID`: Your AWS access key ID.
     - `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key.
     - `AWS_REGION`: The AWS region (e.g., `us-west-2`).
     - `AWS_ACCOUNT_ID`: Your AWS account ID.

3. **Node.js Application**:
   - Ensure you have a `Dockerfile` in your project root with the following content:
     ```dockerfile
    FROM node:14
    WORKDIR /usr/src/app
    COPY package.json .
    RUN npm install 
    COPY . .
    EXPOSE 3000
    CMD ["node", "index.js"]
     ```

## Usage
- On every push to the `main` branch, the GitHub Actions workflow will trigger, build the Docker image, push it to Amazon ECR, and update the ECS service to use the new image.

## Terraform Configuration

### Files
- `main.tf`: The main Terraform configuration file.

### Example `main.tf`
```hcl
provider "aws" {
  region = "us-west-2"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rtable" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.rtable.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.rtable.id
}

resource "aws_security_group" "allow_all" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "main" {
  name = "hello-world-cluster"
}

resource "aws_ecs_task_definition" "hello_world" {
  family                   = "hello-world-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "hello-world"
      image     = "node:14-alpine"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      command = ["node", "-e", "require('http').createServer((req, res) => res.end('Hello World!')).listen(80)"]
    }
  ])
}

resource "aws_lb" "lb" {
  name               = "hello-world-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_all.id]
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
}

resource "aws_lb_target_group" "tg" {
  name         = "hello-world-tg"
  port         = 80
  protocol     = "HTTP"
  vpc_id       = aws_vpc.main.id
  target_type  = "ip"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_ecs_service" "hello_world" {
  name            = "hello-world-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.hello_world.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
    security_groups = [aws_security_group.allow_all.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "hello-world"
    container_port   = 80
  }
}


### Commands
terraform init
terraform validate
terraform apply

### Workflow Explanation
The GitHub Actions workflow is defined in .github/workflows/main.yml:

```yml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v2
    
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build, tag, and push image to Amazon ECR
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: hello-world
          IMAGE_TAG: latest
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Deploy to ECS
        env:
          ECS_CLUSTER: hello-world-cluster
          ECS_SERVICE: hello-world-service
          IMAGE_URI: ${{ steps.login-ecr.outputs.registry }}/hello-world:latest
        run: |
          aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --force-new-deployment --region ${{ secrets.AWS_REGION }}
```

Steps Explanation
Check out code: Checks out the latest code from the main branch.
Configure AWS credentials: Configures AWS credentials using GitHub secrets.
Login to Amazon ECR: Logs into Amazon ECR to push Docker images.
Build, tag, and push image to Amazon ECR: Builds the Docker image, tags it, and pushes it to ECR.
Deploy to ECS: Updates the ECS service with the new image and forces a new deployment.


