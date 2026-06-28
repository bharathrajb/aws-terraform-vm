pipeline {
    agent any

     environment {
        // These pull dynamically from your Jenkins credentials store at runtime.
        // DO NOT paste your actual secret keys inside these strings!
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        
        TF_VAR_ssh_public_key = credentials('aws-ssh-public-key')
    }
    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                dir('build-ec2') {
                    sh 'terraform init -input=false'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('build-ec2') {
                    sh 'terraform plan -input=false'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('build-ec2') {
                    // Automating the confirmation prompt out of the way
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
            echo "Deployment failed. Review the console pipeline logs for errors."
        }
    }
}
