# Frontend app lives here

Copy your Vite app (the folder that contains `package.json`) into this `app/` directory.

Example:
- Local dev folder: `C:\Users\ariel\lab_project`
- Repo destination: `...\dlagroup-serverless-webapp-cicd\app`

The CodeBuild buildspec is already wired to:
- `cd app`
- run the build command
- sync the build output to the **site bucket**

Defaults (can be overridden via Terraform vars):
- `frontend_app_dir` = `app`
- `frontend_build_command` = `npm ci && npm run build`
- `frontend_build_output_dir` = `dist`
