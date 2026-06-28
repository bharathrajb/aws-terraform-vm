pipeline {
    agent any

    environment {
        // --- PERFORMANCE OPTIMIZATION ---
        // Tells Terraform to read/write plugins from the local server disk instead of downloading them every time
        TF_PLUGIN_CACHE_DIR   = '/var/lib/jenkins/.terraform.d/plugin-cache'

        // --- SECURITY CREDENTIAL BINDINGS ---
        // Pulls tokens safely out of your secure Jenkins Credentials store at runtime
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        
        // Injects your public key directly into the "ssh_public_key" variable inside your main.tf
        TF_VAR_ssh_public_key = credentials('aws-ssh-public-key')
    }

    stages {
        stage('Checkout Code') {
            steps {
                // Pulls the latest code cleanly from your GitHub repository branch
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                dir('build-ec2') {
                    // Non-interactive initialization pointing to your remote S3 backend
                    sh 'terraform init -input=false'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('build-ec2') {
                    // Generates the spec map of what will be created in AWS
                    sh 'terraform plan -input=false'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('build-ec2') {
                    // Deploys the RHEL 9 instances and installs Nginx across regions automatically
                    sh 'terraform apply -auto-approve -input=false'
                }
            }
        }
    }

    post {
        success {
            echo "Infrastructure successfully deployed across regions!"
        }
        failure {
            echo "Deployment failed. Review the console pipeline logs above for errors."
        }
    }
}
