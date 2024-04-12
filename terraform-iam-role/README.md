# Create IAM Policy for deployment by pike

## System

### Requirements

- Terraform = 1.7.2
- aws-cli >= 1.29.X

## Deploy

### Install tools

Install serverless, python venv and terraform on mac

```bash
# At project root dir
cd (project_root/)serverless
python -m venv .venv

brew install tfenv
tfenv install 1.7.2
tfenv use 1.7.2
```

### Install Packages

### Deploy AWS Resources by Terraform

#### 1. Edit Terraform config file

Copy sample file and edit variables for your env

```bash
cd (project_root_dir)/terraform-iam-role
cp terraform.tfvars.sample terraform.tfvars
vi terraform.tfvars
```

### 2. Set AWS Profile

##### If use aws profile

```bash
export AWS_SDK_LOAD_CONFIG=1
export AWS_PROFILE=your-aws-profile-name
export AWS_REGION="ap-northeast-1"
```

##### if use aws-vault

```bash
export AWS_REGION="ap-northeast-1"
aws-vault exec your-aws-role-for-create-iam-policy
```

The role needs below policies

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:GetPolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:SetDefaultPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:GetPolicyVersion",
        "iam:ListRolePolicies"
      ],
      "Resource": [
        "arn:aws:iam::your-aws-account-id:policy/*",
        "arn:aws:iam::your-aws-account-id:role/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iam:GetPolicy",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:ListPolicies",
        "iam:ListAttachedRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:CreateRole",
        "iam:UpdateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::your-deployment-bucket"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::your-deployment-bucket/*"]
    }
  ]
}
```

### 3. Execute terraform init

```bash
terraform init
terraform init -backend-config="bucket=your-deployment" -backend-config="key=terraform/your-project/terraform.tfstate" -backend-config="region=ap-northeast-1"
```

### 4. Execute terraform apply

```bash
terraform apply -auto-approve -var-file=./terraform.tfvars
```

## For Development

If you need to create definition, execute as below

Install pike on mac

```bash
brew tap jameswoolfenden/homebrew-tap
brew install jameswoolfenden/tap/pike
```

Create Terraform file to create IAM policy

```bash
cd (project_root_dir)/terraform
pike scan -d . -i -e > ../terraform-iam-role/main.tf
```

Edit generated file

```bash
cd ../terraform-iam-role
vi main.tf
```
