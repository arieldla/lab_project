# 1) See what creds the CLI is using (env > config > profile)

aws configure list

# 2) Make sure no env vars are overriding your profile

Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue

# 3) Explicitly pick the right profile (replace IAMadmin with yours)

$PROFILE = "IAMadmin"

# 4) Who am I? (confirms the keys exist & are active)

aws sts get-caller-identity --profile $PROFILE

# Pick the profile Terraform should use

$env:AWS_PROFILE="IAMadmin-sso"

# Login (creates fresh cached token)

aws sso login --profile $env:AWS_PROFILE

# Sanity check (MUST work)

aws sts get-caller-identity
