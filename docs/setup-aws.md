# AWS Secrets Manager setup

Store the Entra app credentials once and let every Rails application read them. Rotating the
secret then updates every application without a restart.

## 1. Create the secret (one per environment)

```shell
aws secretsmanager create-secret \
  --region us-east-1 \
  --name shared/entra-mailer/production \
  --secret-string '{"tenant_id":"<tenant-id>","client_id":"<client-id>","client_secret":"<secret-value>"}'
```

Repeat for `shared/entra-mailer/staging` if staging uses its own Entra app or secret. The name is
up to you; the gem reads whatever `aws_secret_id` you configure.

## 2. Grant read access to each application

Attach to each application's IAM role (EC2 instance profile, ECS task role, ...), for both web and
background-job hosts:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:shared/entra-mailer/*"
    }
  ]
}
```

If the secret uses a customer-managed KMS key, also allow `kms:Decrypt` on that key.
Grant nothing broader (no `secretsmanager:*`).

## 3. Network

Allow outbound HTTPS (443) from application hosts to:

- `login.microsoftonline.com` (tokens)
- `graph.microsoft.com` (sendMail)
- `secretsmanager.<region>.amazonaws.com` (or a VPC endpoint)

## 4. Configure the application

```ruby
# Gemfile
gem "ms_graph_mailer", github: "VandaPharma/ms_graph_mailer", tag: "v1.0.0"
gem "aws-sdk-secretsmanager", require: false
```

```ruby
config.aws_secret_id        = "shared/entra-mailer/#{Rails.env}"
config.aws_region           = "us-east-1"
config.aws_secret_ttl       = 600
```

No AWS keys go into the app: the SDK uses the instance or task role. Do not also set
`tenant` / `client_id` / `client_secret` in the initializer (or set
`config.credentials_provider = :aws_secrets_manager` explicitly).

## 5. Verify from a host

Without printing the secret:

```shell
aws secretsmanager get-secret-value --region us-east-1 --secret-id shared/entra-mailer/production \
  --query SecretString --output text | jq 'del(.client_secret)'
```

Then, in the app directory:

```shell
bin/rails ms_graph_mailer:check
```
