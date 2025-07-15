# Terraform StaticSite on AWS

Deploy AWS Resources for Static Site by Terraform

## Create AWS S3 Bucket for terraform state and frontend config

Create S3 Bucket named "your-terraform-config-bucket"

## Preparation

You need below

- aws-cli == 2.27.X
- Terraform == 1.12.1

### Example Installation Terraform by tfenv on mac

```bash
brew install tfenv
tfenv install 1.12.1
tfenv use 1.12.1
```

#### Edit Terraform config file

Copy sample file and edit variables for your env

```bash
cd (project_root_dir)
cp terraform.tfvars.sample terraform.tfvars
vi terraform.tfvars
```

#### Setup Lambda@Edge function (Optional)

If you want to use Lambda@Edge function, you need to set up the function.

##### Copy and Edit Lambda@Edge config file

Copy sample file and edit variables for your Lambda@Edge env

```bash
cp functions/src/viewer_request/configs/config.js.sample  functions/src/viewer_request/configs/config.js
vi functions/src/viewer_request/configs/config.js
```

##### Zip Lambda@Edge function

```bash
sh bin/package_lambda_edge_function.sh
```

#### 2. Set AWS profile name to environment variable

```bash
export AWS_PROFILE=your-aws-profile-name
export AWS_REGION="ap-northeast-1"
```

#### 3. Execute terraform init

Command Example to init

```bash
terraform init -backend-config="bucket=your-deployment" -backend-config="key=terraform/your-project/terraform.tfstate" -backend-config="region=ap-northeast-1"
```

#### 4. Execute terraform apply

```bash
terraform apply -var-file=./terraform.tfvars
```
