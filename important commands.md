You want the Access Token from Cognito

$region   = "us-east-1"
$clientId = "1jfbsvc09p97kr1oj9dp9gcfk2" # from terraform output
$user     = "thedlagroupinc@gmail.com"
$pass = "YOUR_PASSWORD" #<--- change that#

$auth = aws cognito-idp initiate-auth `
  --region $region `
  --auth-flow USER_PASSWORD_AUTH `
  --client-id $clientId `
  --auth-parameters "USERNAME=$user,PASSWORD=$pass" | ConvertFrom-Json

$accessToken = $auth.AuthenticationResult.AccessToken
$accessToken

rebuild + upload:
cd ..\app
npm run build

cd ..\infra
aws s3 sync ..\app\build s3://dlagroup-serverless-webapp-site-640168421612 --delete
aws cloudfront create-invalidation --distribution-id E12VBV94CML0RC --paths "/\*"
