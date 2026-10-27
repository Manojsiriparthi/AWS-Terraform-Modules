# 🔧 Jenkins Terraform Pipeline — Complete Setup Guide

> **Spoon-feeding method — open this, click this, enter this, save this.**
> Follow every step in order. Do not skip any step.

---

## 📋 Table of Contents

1. [What This Pipeline Does](#1-what-this-pipeline-does)
2. [Prerequisites — Before You Start](#2-prerequisites--before-you-start)
3. [Step 1 — Install Jenkins Plugins](#3-step-1--install-jenkins-plugins)
4. [Step 2 — Add Credentials in Jenkins](#4-step-2--add-credentials-in-jenkins)
5. [Step 3 — Create the Pipeline Job](#5-step-3--create-the-pipeline-job)
6. [Step 4 — Paste the Jenkinsfile](#6-step-4--paste-the-jenkinsfile)
7. [Step 5 — Run the Pipeline](#7-step-5--run-the-pipeline)
8. [Pipeline Explanation — Every Line](#8-pipeline-explanation--every-line)

---

## 1. What This Pipeline Does

```
When you click "Build", the pipeline runs these stages in order:

  Stage 1  →  Checkout        Pull code from GitHub using url + branch in pipeline
  Stage 2  →  Init            terraform init  (setup providers + S3 backend)
  Stage 3  →  Format          terraform fmt   (check code style)
  Stage 4  →  Validate        terraform validate  (check syntax)
  Stage 5  →  Plan            terraform plan  (save plan to file)
  Stage 6  →  Show Plan       Print human-readable diff to console
  Stage 7  →  Approval        PROD ONLY — human must click Approve
  Stage 8  →  Apply/Destroy   Execute the saved plan
  Stage 9  →  Output          Print deployed resource details
```

**Before each run you choose:**
- **ENVIRONMENT** → `dev` / `test` / `prod`
- **ACTION** → `apply` (create infra) / `destroy` (delete infra)

**Approval rules:**
- `dev`  → runs all stages automatically, no human needed
- `test` → runs all stages automatically, no human needed
- `prod` → pauses at Stage 7 and waits for a human to click **Approve**

---

## 2. Prerequisites — Before You Start

You need these things ready before starting:

| What | Details |
|------|---------|
| Jenkins installed and running | Already installed on your EC2 via the user_data script |
| Jenkins URL | `http://YOUR-EC2-PUBLIC-IP:8080` |
| AWS IAM user with programmatic access | AWS Console → IAM → Users → Create user → Access keys |
| S3 bucket for Terraform state | See the main README Quick Start section |
| DynamoDB table for state locking | See the main README Quick Start section |

---

## 3. Step 1 — Install Jenkins Plugins

> Plugins add extra features to Jenkins. We need 4 plugins.

### 3a. Open Plugin Manager

```
1. Open your browser
2. Go to:   http://YOUR-EC2-IP:8080
3. Log in with your Jenkins admin password
4. On the left sidebar, click:   "Manage Jenkins"
5. Click:   "Manage Plugins"
6. Click the tab at the top:   "Available plugins"
```

### 3b. Search and Install Each Plugin

In the search box at the top, type the plugin name.
Tick the checkbox next to it. Repeat for all 4.

| # | Type this in search box | Why we need it |
|---|------------------------|----------------|
| 1 | `Pipeline` | Core support — stages, steps, when, post |
| 2 | `Credentials Binding` | Safely injects secrets (AWS keys, passwords) as env vars |
| 3 | `AnsiColor` | Coloured console output — easier to read (optional) |
| 4 | `Email Extension` | Sends email notifications on success/failure (optional) |

```
After ticking all checkboxes:

  1. Scroll to the bottom of the page
  2. Click:   "Install without restart"   (the green button)
  3. Wait for each plugin to show:   "Success"
  4. Click:   "Restart Jenkins when installation is complete and no jobs are running"
  5. Wait for the page to reload
  6. Log back in
```

---

## 4. Step 2 — Add Credentials in Jenkins

> Credentials are secrets stored securely inside Jenkins.
> Jenkins encrypts them and shows them as `****` in all console logs.
> The Jenkinsfile refers to each credential by its **ID** —
> the ID you type here must match the ID in the Jenkinsfile exactly.

### How to Open the Credentials Page

```
1. On the left sidebar, click:   "Manage Jenkins"
2. Click:   "Manage Credentials"
3. Under "Stores scoped to Jenkins", click:   "System"
4. Click:   "Global credentials (unrestricted)"
5. On the top right, click:   "+ Add Credentials"
```

You will now see a form. Fill it in exactly as shown below for each credential.
After filling in each one, click **Create** at the bottom.
Then click **+ Add Credentials** again to add the next one.

---

### Credential 1 — AWS Access Keys

**Purpose:** Lets Jenkins call AWS APIs on your behalf (create EC2, VPC, RDS, etc.)

**Where to get your AWS keys:**
```
1. Open:   https://console.aws.amazon.com
2. Click your account name in the top right corner
3. Click:   "Security credentials"
4. Scroll down to:   "Access keys"
5. Click:   "Create access key"
6. Select:   "Application running outside AWS"
7. Click:   "Next" → "Create access key"
8. You will see two values — copy them both:
     Access key ID      →  looks like:  AKIAIOSFODNN7EXAMPLE
     Secret access key  →  looks like:  wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**Fill in the Jenkins form:**
```
Kind        →  click dropdown  →  select:  "Username with password"
Scope       →  leave as:  "Global"
Username    →  paste your Access key ID
                 example:  AKIAIOSFODNN7EXAMPLE
Password    →  paste your Secret access key
                 example:  wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
ID          →  type exactly:  aws-credentials
                 ⚠️  Must be exactly this — no spaces, no capitals
Description →  type:  AWS access keys for Terraform
```

Click: **Create**

---

### Credential 2 — S3 Bucket Name for Terraform State

**Purpose:** Tells Jenkins the name of your S3 bucket where Terraform saves its state file.

**What value to use:**
The name of the S3 bucket you created. Example: `terraform-state-123456789012`

**Fill in the Jenkins form:**
```
Kind        →  click dropdown  →  select:  "Secret text"
Scope       →  leave as:  "Global"
Secret      →  type your S3 bucket name
                 example:  terraform-state-123456789012
ID          →  type exactly:  terraform-backend-bucket
                 ⚠️  Must be exactly this
Description →  type:  S3 bucket name for Terraform remote state
```

Click: **Create**

---

### Credential 3 — Database Password for Dev

**Purpose:** The master password Terraform sets on the RDS MySQL database in dev.

**Fill in the Jenkins form:**
```
Kind        →  click dropdown  →  select:  "Secret text"
Scope       →  leave as:  "Global"
Secret      →  type a strong password of your choice
                 example:  DevDb!Pass2024#Secure
                 Rules: minimum 8 characters, mix of upper, lower, numbers, symbols
ID          →  type exactly:  terraform-db-password-dev
                 ⚠️  Must be exactly this
Description →  type:  RDS master password for dev environment
```

Click: **Create**

---

### Credential 4 — Database Password for Test

**Purpose:** Same as above but for the test environment.

**Fill in the Jenkins form:**
```
Kind        →  click dropdown  →  select:  "Secret text"
Scope       →  leave as:  "Global"
Secret      →  type a strong password (can be different from dev)
                 example:  TestDb!Pass2024#Secure
ID          →  type exactly:  terraform-db-password-test
                 ⚠️  Must be exactly this
Description →  type:  RDS master password for test environment
```

Click: **Create**

---

### Credential 5 — Database Password for Prod

**Purpose:** Same as above but for the prod environment. Use a different, stronger password.

**Fill in the Jenkins form:**
```
Kind        →  click dropdown  →  select:  "Secret text"
Scope       →  leave as:  "Global"
Secret      →  type a strong password  (must be DIFFERENT from dev and test)
                 example:  ProdDb!Ultra$ecure2024#X
ID          →  type exactly:  terraform-db-password-prod
                 ⚠️  Must be exactly this
Description →  type:  RDS master password for prod environment
```

Click: **Create**

---

### ✅ Check All 5 Credentials Exist

After adding all five, you should see this on the credentials page:

```
┌──────────────────────────────────────┬────────────────────────────────────────┐
│  ID                                  │  Description                           │
├──────────────────────────────────────┼────────────────────────────────────────┤
│  aws-credentials                     │  AWS access keys for Terraform         │
│  terraform-backend-bucket            │  S3 bucket name for Terraform state    │
│  terraform-db-password-dev           │  RDS master password for dev           │
│  terraform-db-password-test          │  RDS master password for test          │
│  terraform-db-password-prod          │  RDS master password for prod          │
└──────────────────────────────────────┴────────────────────────────────────────┘
```

> ⚠️ The IDs in the left column must match exactly what is shown.
> The Jenkinsfile uses these exact strings. One typo = credential not found = pipeline fails.

---

## 5. Step 3 — Create the Pipeline Job

### 5a. Open Jenkins and Create a New Item

```
1. Go to:   http://YOUR-EC2-IP:8080
2. On the left sidebar, click:   "New Item"
3. In the box that says "Enter an item name", type:
         terraform-infrastructure-pipeline
4. Below the name box, click:   "Pipeline"
   (it shows a small pipe diagram icon)
5. Click:   "OK"   at the bottom
```

You are now on the job configuration page.

### 5b. General Settings

```
Scroll down until you see the "General" heading.

Find the checkbox that says:   "This project is parameterized"
Tick it  ✅

  Why?
  The Jenkinsfile defines parameters (ENVIRONMENT, ACTION dropdowns).
  Ticking this box tells Jenkins: "show a form before each build."
  Without ticking it, Jenkins just shows "Build Now" with no form.
```

### 5c. Build Triggers (Optional)

```
Scroll down to the "Build Triggers" section.

If you want the pipeline to run automatically when code changes:
  ✅ Tick:  "Poll SCM"
  In the Schedule box type:   H/5 * * * *
  (checks for changes every 5 minutes)

If you want to trigger builds manually only, leave everything unticked.
```

### 5d. Scroll to the Pipeline Section

```
Continue scrolling down until you reach the "Pipeline" section.
It is at the very bottom of the configuration page.
```

---

## 6. Step 4 — Paste the Jenkinsfile

This is where you put the pipeline code directly into Jenkins.

### 6a. Set the Definition

```
In the "Pipeline" section, find the "Definition" dropdown.
It currently says:   "Pipeline script"
Leave it as:         "Pipeline script"

  (This means: type or paste the pipeline code directly here)
```

### 6b. Open the Jenkinsfile on Your Computer

```
On your computer, open this file in any text editor:

  AWS-Terraform-Modules/jenkins/Jenkinsfile

  Before copying, find this line near the top of Stage 1:
    url : 'https://github.com/YOUR-USERNAME/AWS-Terraform-Modules.git',

  Replace  YOUR-USERNAME  with your actual GitHub username.
  Example:
    url : 'https://github.com/akhildev/AWS-Terraform-Modules.git',

  Save the file.

  Then:  Select ALL the text  (Ctrl + A)
         Copy it              (Ctrl + C)
```

### 6c. Paste into Jenkins

```
Back in Jenkins, in the "Pipeline" section you see a large white text area
with the label "Script".

  1. Click inside the white text area
  2. Select all existing text if any  (Ctrl + A)
  3. Delete it
  4. Paste your copied Jenkinsfile content  (Ctrl + V)

You should now see the full pipeline code in the text area.
```

### 6d. Save the Job

```
Scroll to the very bottom of the page.
Click:   "Save"   (the blue button)
```

---

## 7. Step 5 — Run the Pipeline

### 7a. First Build — Load the Parameters

```
You are now on the pipeline job's main page.
The left sidebar shows:   "Build Now"

1. Click:   "Build Now"
   Jenkins runs once to read the pipeline code and register the parameters.
   This first build may show as grey (not run) or complete quickly — that is normal.

2. Wait about 10 seconds, then refresh the page  (F5 or browser refresh)

3. The left sidebar should now show:   "Build with Parameters"
   instead of "Build Now"
   If it still says "Build Now", wait a few more seconds and refresh again.
```

### 7b. Run with Parameters — Your First Deployment

```
1. Click:   "Build with Parameters"

2. Jenkins shows a form with three fields:

   ┌──────────────────────────────────────────────────────────┐
   │                                                          │
   │  ENVIRONMENT    [  dev  ▼ ]                              │
   │  (dropdown)                                              │
   │                                                          │
   │  ACTION         [  apply  ▼ ]                            │
   │  (dropdown)                                              │
   │                                                          │
   │  NOTIFY_EMAIL   [                    ]                   │
   │  (text box)                                              │
   │                                                          │
   └──────────────────────────────────────────────────────────┘

3. For your first run, set:
     ENVIRONMENT   →  click the dropdown  →  select:  dev
     ACTION        →  click the dropdown  →  select:  apply
     NOTIFY_EMAIL  →  leave blank

4. Click:   "Build"   (the blue button at the bottom of the form)
```

### 7c. Watch the Pipeline Run

```
1. A new item appears in "Build History" on the left sidebar.
   It shows a spinning circle while running.

2. Click the build number  (example: "#1")

3. You see two options:
   a) Click:  "Console Output"
      → Shows the live log output line by line as it runs.
        You see the exact commands Terraform is running.

   b) Click:  "Pipeline Steps"  or go back and see the stage boxes
      → Shows coloured boxes for each stage:
          Green  = passed
          Red    = failed
          Grey   = skipped (because of when{} condition)
```

### 7d. What the Console Output Looks Like

```
Stage 1 — Checkout:
  Cloning into '/var/lib/jenkins/workspace/terraform-infrastructure-pipeline'...
  Code pulled successfully from GitHub

Stage 2 — Init:
  Initializing the backend...
  Successfully configured the backend "s3"!
  Terraform has been successfully initialized!

Stage 5 — Plan:
  Plan: 47 to add, 0 to change, 0 to destroy.

Stage 6 — Show Plan:
  + aws_vpc.main will be created
  + aws_internet_gateway.main will be created
  ...

Stage 8 — Apply:
  aws_vpc.main: Creating...
  aws_vpc.main: Creation complete [id=vpc-0abc123]
  Apply complete! Resources: 47 added, 0 changed, 0 destroyed.

Stage 9 — Output:
  ec2_public_ips = ["52.10.20.30"]
  eks_cluster_name = "dev-eks-cluster"
  rds_primary_endpoint = "dev-mysql.xyz.rds.amazonaws.com"
```

### 7e. Running for PROD — Manual Approval Flow

```
When you pick ENVIRONMENT = prod and click Build:

  Stages 1 to 6 run automatically (checkout, init, fmt, validate, plan, show plan).

  At Stage 7 (Prod Manual Approval):

    Jenkins PAUSES here and shows a popup in the UI:

    ┌──────────────────────────────────────────────────────────┐
    │                                                          │
    │  PROD APPLY — approve or abort?                         │
    │                                                          │
    │  [ Approve and Continue ]     [ Abort ]                  │
    │                                                          │
    └──────────────────────────────────────────────────────────┘

    Before clicking, scroll up in the console output and read
    Stage 6 (Show Plan) carefully.
    Look for any lines with  -/+  which means a resource will be REPLACED.

    If the plan looks correct:
      Click:   "Approve and Continue"
      → Stages 8 and 9 run automatically.

    If something looks wrong:
      Click:   "Abort"
      → Pipeline stops. Nothing is changed in AWS.

    ⚠️  If nobody clicks within 30 minutes, the pipeline aborts automatically.
```

### 7f. Running Destroy

```
To delete all infrastructure in an environment:

  ENVIRONMENT  →  select:  dev  (or test, or prod)
  ACTION       →  select:  destroy

  The pipeline will:
    Stage 5  →  run  terraform plan -destroy  (shows what will be deleted)
    Stage 6  →  print every resource marked with  -  (will be deleted)
    Stage 7  →  if prod, requires approval before deleting
    Stage 8  →  runs  terraform apply  on the destroy plan

  After destroy, Stage 9 (Output) is skipped — nothing left to output.
```

---

## 8. Pipeline Explanation — Every Line

> This section explains every part of the `Jenkinsfile` code.
> Open `jenkins/Jenkinsfile` alongside this guide.

---

### The Outer Wrapper — `pipeline { }`

```groovy
pipeline {

}
```

Every declarative Jenkins pipeline must start with `pipeline {` and end with `}`.
Everything else — agent, parameters, stages, post — lives inside this block.
Think of it like the outer shell of a program.

---

### `agent any`

```groovy
agent any
```

Tells Jenkins **on which machine** to run the pipeline.
`any` means use whichever Jenkins worker is currently free.
Since Jenkins is running on the EC2 instance itself, `any` is correct here.

---

### `parameters { }` — The Input Form

```groovy
parameters {

    choice(
        name        : 'ENVIRONMENT',
        choices     : ['dev', 'test', 'prod'],
        description : 'Which environment to deploy?'
    )

    choice(
        name        : 'ACTION',
        choices     : ['apply', 'destroy'],
        description : 'apply = create/update  |  destroy = delete all'
    )

    string(
        name         : 'NOTIFY_EMAIL',
        defaultValue : '',
        description  : 'Optional email to notify on completion'
    )
}
```

`parameters { }` creates the form you fill in before clicking Build.

- `choice(...)` → creates a **dropdown menu**
  - `name` → the variable name. Access it anywhere in the pipeline as `params.ENVIRONMENT`
  - `choices` → the list of options in the dropdown
  - `description` → helper text shown next to the field in the UI

- `string(...)` → creates a **text input box**
  - `defaultValue` → what is pre-filled in the box (empty here)

---

### `environment { }` — Pipeline Variables

```groovy
environment {
    ENV_DIR            = "environments/${params.ENVIRONMENT}"
    TFVARS_FILE        = "${params.ENVIRONMENT}.tfvars"
    PLAN_FILE          = "tfplan-${params.ENVIRONMENT}"
    TF_IN_AUTOMATION   = "true"
    AWS_DEFAULT_REGION = "us-east-1"
}
```

`environment { }` defines variables available to **every single stage** below.
Works like `export VAR=value` at the top of a bash script.

- `ENV_DIR` → the folder path to cd into. If user picked `dev`, this becomes `environments/dev`
- `TFVARS_FILE` → the tfvars file to use. Becomes `dev.tfvars`, `test.tfvars`, or `prod.tfvars`
- `PLAN_FILE` → the saved plan filename. Becomes `tfplan-dev`, `tfplan-test`, or `tfplan-prod`
- `TF_IN_AUTOMATION = "true"` → tells Terraform it is running inside a CI/CD pipeline.
  Without this, Terraform may print interactive prompts like "Enter a value:" and
  the pipeline will hang forever waiting for keyboard input that never comes.
- Use these variables anywhere below as `${ENV_DIR}`, `${PLAN_FILE}` etc.

---

### `stages { }` and `stage('Name') { }`

```groovy
stages {

    stage('Checkout') {
        steps {
            ...commands here...
        }
    }

    stage('Terraform Init') {
        steps {
            ...commands here...
        }
    }

}
```

- `stages { }` is the container block that holds all your stages.
- `stage('Name') { }` is one named step. Jenkins draws each stage as a coloured box in the UI.
- `steps { }` is where the actual commands go inside a stage.

---

### `sh '...'` — Run a Shell Command

```groovy
sh 'terraform validate'
```

`sh` runs a shell command on the agent. Same as typing in a terminal.

Three ways to write it:

```groovy
sh 'single line command'               // single quotes — no variable substitution

sh "echo Hello ${params.ENVIRONMENT}"  // double quotes — Jenkins variables work

sh '''
    multi
    line
    command
'''                                    // triple single quotes — multi-line, no variables

sh """
    echo "Environment is: ${ENV_DIR}"
"""                                    // triple double quotes — multi-line WITH variables
```

---

### Stage 1 — Checkout

```groovy
stage('Checkout') {
    steps {
        git(
            url   : 'https://github.com/YOUR-USERNAME/AWS-Terraform-Modules.git',
            branch: 'main'
        )
    }
}
```

- `git(url: '...', branch: '...')` → Jenkins built-in step that clones the repo
  directly inside the pipeline code itself.
- **No SCM configuration needed on the Jenkins job page.**
  The URL and branch live right here in the Jenkinsfile — easy to see and change.
- `url` → your GitHub repository HTTPS URL.
  Replace `YOUR-USERNAME` with your actual GitHub username.
  Example: `https://github.com/akhildev/AWS-Terraform-Modules.git`
- `branch` → which branch to pull from.
  `'main'` is the default branch name on GitHub.
  Change to `'dev'` or `'feature/xyz'` if needed.

> ⚠️ **Before running:** Open `jenkins/Jenkinsfile`, find line with
> `url : 'https://github.com/YOUR-USERNAME/...'`
> and replace `YOUR-USERNAME` with your real GitHub username.

---

### `withCredentials { }` — Injecting Secrets

```groovy
withCredentials([
    usernamePassword(
        credentialsId   : 'aws-credentials',
        usernameVariable: 'AWS_ACCESS_KEY_ID',
        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
    ),
    string(
        credentialsId: 'terraform-backend-bucket',
        variable     : 'TF_STATE_BUCKET'
    )
]) {
    // Inside here, the variables are available as env vars
    sh 'echo $AWS_ACCESS_KEY_ID'  // prints ****  (masked)
}
```

`withCredentials([...]) { }` pulls secrets from Jenkins and makes them
available as environment variables only inside the `{ }` block.
Outside the block they do not exist.

- `credentialsId : 'aws-credentials'` → the **ID** you set when creating the credential.
  This is how Jenkins finds the right secret.
- `usernameVariable: 'AWS_ACCESS_KEY_ID'` → the env var name for the username value.
- `passwordVariable: 'AWS_SECRET_ACCESS_KEY'` → the env var name for the password value.
- Terraform and AWS CLI automatically use `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
  when they are present as environment variables.
- Values are always **masked** in the console — shown as `****`.

---

### `dir('path') { }` — Change Directory

```groovy
dir("${ENV_DIR}") {
    sh 'terraform init ...'
    sh 'terraform plan ...'
}
```

`dir('path') { }` changes into the given folder for all commands inside it.
Same as running `cd environments/dev` in your terminal.

Without `dir()`:
```
terraform init runs in the workspace root
It can't find main.tf, variables.tf etc.
Error: no Terraform files found
```

With `dir("environments/dev")`:
```
terraform init runs inside environments/dev/
It finds main.tf, variables.tf, providers.tf etc.
Everything works correctly.
```

---

### Stage 2 — Terraform Init

```groovy
sh '''
    terraform init \
        -backend-config="bucket=$TF_STATE_BUCKET" \
        -backend-config="key=$ENVIRONMENT/terraform.tfstate" \
        -backend-config="region=$AWS_DEFAULT_REGION" \
        -backend-config="dynamodb_table=terraform-lock-$ENVIRONMENT" \
        -backend-config="encrypt=true" \
        -reconfigure \
        -input=false
'''
```

`terraform init` downloads providers and sets up the remote S3 backend.

- `\` at end of line → continue the command on the next line (line continuation).
- Each `-backend-config="..."` passes one key-value pair to the S3 backend config.
  - `bucket` → which S3 bucket stores the state file
  - `key` → the path inside the bucket, e.g. `dev/terraform.tfstate`
  - `dynamodb_table` → the DynamoDB table name used for state locking
  - `encrypt=true` → encrypt the state file at rest in S3
- `-reconfigure` → run init fresh even if already initialised before.
- `-input=false` → never ask for keyboard input. **Mandatory in pipelines.**

---

### Stage 3 — Terraform Format

```groovy
script {
    def fmtStatus = sh(
        script       : 'terraform fmt -check -diff -recursive .',
        returnStatus : true
    )

    if (fmtStatus != 0) {
        echo "WARNING: Some .tf files are not formatted correctly."
        echo "Fix by running:  terraform fmt -recursive"
    } else {
        echo "All .tf files are correctly formatted."
    }
}
```

- `script { }` → allows Groovy code (variables, if/else) inside a `steps` block.
- `def fmtStatus = sh(script: '...', returnStatus: true)` → runs the command and
  **captures the exit code** as a number instead of automatically failing.
  - `returnStatus: true` → give me the number, don't throw an error.
  - Exit 0 → all files formatted. Exit 1 → files need formatting.
- `if (fmtStatus != 0)` → if exit code is anything other than 0, warn the developer.
- This stage warns but does not stop the pipeline. Change `echo` to `error('...')` to make it a hard fail.

---

### Stage 4 — Terraform Validate

```groovy
sh 'terraform validate'
```

`terraform validate` checks syntax and configuration.
It runs completely offline — no AWS calls.

If there is an error (missing argument, wrong type, undefined variable),
the `sh` command gets a non-zero exit code → stage fails → pipeline stops.
This is the correct behaviour — catch errors early before wasting time on a plan.

---

### Stage 5 — Terraform Plan

```groovy
script {
    if (params.ACTION == 'destroy') {
        sh """
            terraform plan \
                -destroy \
                -var-file="${TFVARS_FILE}" \
                -out="${PLAN_FILE}" \
                -input=false
        """
    } else {
        sh """
            terraform plan \
                -var-file="${TFVARS_FILE}" \
                -out="${PLAN_FILE}" \
                -input=false
        """
    }
}
```

- `if (params.ACTION == 'destroy')` → checks what the user picked from the ACTION dropdown.
- `-destroy` → tells plan to compute what would be deleted instead of created.
- `-var-file="${TFVARS_FILE}"` → use `dev.tfvars` or `test.tfvars` or `prod.tfvars`.
- `-out="${PLAN_FILE}"` → **saves the plan** to a binary file called `tfplan-dev`.

Why save the plan to a file?
```
WITHOUT saving:
  Stage 5: terraform plan   → computes what will change
  10 minutes pass (approval stage)
  Stage 8: terraform apply  → computes AGAIN — something might have changed!
  Risk: Stage 8 applies a different plan than what was reviewed.

WITH saving (correct CI/CD approach):
  Stage 5: terraform plan -out=tfplan-dev  → saves plan to file
  Stage 8: terraform apply tfplan-dev      → applies EXACTLY that saved plan
  No surprises. What you reviewed is what runs.
```

---

### Stage 6 — Show Plan

```groovy
sh """
    terraform show -no-color "${PLAN_FILE}"
"""
```

`terraform show PLAN_FILE` converts the binary plan file into human-readable text
and prints it to the console.

- Without this stage: you only see the summary line `Plan: 5 to add, 0 to change, 0 to destroy.`
- With this stage: you see every attribute of every resource that will change.
- `-no-color` → plain text (no ANSI colour codes) — easier to read in Jenkins logs.
- For prod: read this output carefully before clicking Approve in Stage 7.

---

### Stage 7 — Prod Manual Approval

```groovy
stage('Prod Manual Approval') {

    when {
        expression { params.ENVIRONMENT == 'prod' }
    }

    steps {
        timeout(time: 30, unit: 'MINUTES') {
            input(
                message            : "PROD ${params.ACTION.toUpperCase()} — approve or abort?",
                ok                 : 'Approve and Continue',
                submitterParameter : 'APPROVED_BY'
            )
        }
    }
}
```

- `when { expression { ... } }` → only run this stage when the condition is true.
  - `params.ENVIRONMENT == 'prod'` → true only when prod is selected.
  - For dev and test, this entire stage is **skipped automatically** (shown as grey box).

- `timeout(time: 30, unit: 'MINUTES') { }` → if no one clicks Approve within
  30 minutes, the pipeline aborts by itself.

- `input(...)` → pauses the pipeline and shows a button in Jenkins UI.
  - `message` → the text shown to the person approving.
  - `ok` → the label on the green Approve button.
  - `submitterParameter: 'APPROVED_BY'` → captures and stores the username of whoever clicked.

- If someone clicks **Abort**: the pipeline throws an exception and stops.
- If someone clicks **Approve and Continue**: this stage passes, Stage 8 runs.

---

### Stage 8 — Terraform Apply

```groovy
stage('Terraform Apply') {

    when {
        expression { params.ACTION == 'apply' }
    }

    steps {
        sh """
            terraform apply -auto-approve "${PLAN_FILE}"
        """
    }
}
```

- `when { expression { params.ACTION == 'apply' } }` → only runs when ACTION = apply.
- `terraform apply "${PLAN_FILE}"` → executes the **saved plan** from Stage 5.
  This is the exact plan the team reviewed in Stage 6 and (for prod) approved in Stage 7.
- `-auto-approve` → skip the interactive "yes/no" prompt. Safe here because:
  - dev/test: automatic flow, no approval needed, fast iteration.
  - prod: a human already clicked Approve in Stage 7 — the approval already happened.

### Stage 8 — Terraform Destroy

```groovy
stage('Terraform Destroy') {

    when {
        expression { params.ACTION == 'destroy' }
    }

    steps {
        sh """
            terraform apply -auto-approve "${PLAN_FILE}"
        """
    }
}
```

- Same structure as Apply but runs only when ACTION = destroy.
- The `PLAN_FILE` was created with `-destroy` flag in Stage 5, so it is a destroy plan.
- `terraform apply` on a destroy plan = deletes all the resources in that plan.

---

### Stage 9 — Terraform Output

```groovy
stage('Terraform Output') {

    when {
        expression { params.ACTION == 'apply' }
    }

    steps {
        sh 'terraform output'
    }
}
```

- Runs only after apply (not after destroy — everything was deleted).
- `terraform output` prints all values defined in `outputs.tf`:
  EC2 public IPs, EKS cluster endpoint, RDS endpoint, S3 bucket name, SNS ARN, etc.
- Use these values to connect to your deployed resources without opening AWS Console.

---

### `post { }` — After All Stages

```groovy
post {

    always {
        sh "rm -f ${ENV_DIR}/${PLAN_FILE}"
        echo "Pipeline result: ${currentBuild.currentResult}"
    }

    success {
        echo "SUCCESS: Terraform ${params.ACTION} completed for ${params.ENVIRONMENT}"
    }

    failure {
        echo "FAILED: Check console output for the error"
    }

    aborted {
        echo "ABORTED: Stopped manually or approval timed out"
    }
}
```

`post { }` runs after all stages complete, regardless of whether they passed or failed.

- `always { }` → runs no matter what.
  - `rm -f ${PLAN_FILE}` → deletes the binary plan file from the workspace for security.
  - `currentBuild.currentResult` → Jenkins built-in variable. Value is `"SUCCESS"`, `"FAILURE"`, or `"ABORTED"`.
- `success { }` → only runs when every stage passed.
- `failure { }` → only runs when any stage failed.
- `aborted { }` → only runs when someone stopped the pipeline manually,
  or the 30-minute approval timeout expired.

---

## Quick Reference — Credential IDs

```
These IDs must be created in Jenkins EXACTLY as shown:

  Credential ID                  │  Stores
  ───────────────────────────────┼──────────────────────────────────────
  aws-credentials                │  AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
  terraform-backend-bucket       │  Name of S3 bucket for Terraform state
  terraform-db-password-dev      │  RDS master password for dev
  terraform-db-password-test     │  RDS master password for test
  terraform-db-password-prod     │  RDS master password for prod
```

---

## Quick Reference — Environment Behaviour

```
  ENVIRONMENT │ ACTION  │ Approval?      │ Stages that run
  ────────────┼─────────┼────────────────┼──────────────────────────────────────
  dev         │ apply   │ None — auto    │ 1 2 3 4 5 6  [7 skipped]  8-apply 9
  dev         │ destroy │ None — auto    │ 1 2 3 4 5 6  [7 skipped]  8-destroy
  test        │ apply   │ None — auto    │ 1 2 3 4 5 6  [7 skipped]  8-apply 9
  test        │ destroy │ None — auto    │ 1 2 3 4 5 6  [7 skipped]  8-destroy
  prod        │ apply   │ Human required │ 1 2 3 4 5 6  7-PAUSE      8-apply 9
  prod        │ destroy │ Human required │ 1 2 3 4 5 6  7-PAUSE      8-destroy
```
