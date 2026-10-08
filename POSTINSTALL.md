AnythingLLM on Cloudron - Post-Install
======================================

After the app is installed, complete the initial setup from the web interface.

1. Open the App

2. Default Access Mode
----------------------
- The Cloudron package starts in AnythingLLM's default Docker behavior: `single-user mode`.
- In this mode there is no initial login screen and no first admin account is created automatically.
- Anyone who can reach the app can use the single shared instance unless you later enable multi-user mode or set an instance password inside the UI.

3. Optional: Enable Multi-User Mode
-----------------------------------
- If you want per-user logins, open the app settings and enable multi-user mode.
- That flow creates the first administrator account inside the app.
- Upstream treats this change as one-way, so do not enable it unless you want account-based access control.

4. Configure Providers
----------------------
- Configure your preferred LLM, embedding, speech, or tool providers from the AnythingLLM settings UI.
- Provider settings written by the app are persisted through the Cloudron data volume.

5. Persistent Paths
-------------------
- Main application storage lives under `/app/data/storage`.
- Collector hot folder imports live under `/app/data/collector/hotdir`.
- Collector outputs live under `/app/data/collector/outputs`.
- Runtime configuration lives in `/app/data/server.env`.

6. Operational Notes
--------------------
- Cloudron backups include `/app/data`.
- The package initializes its required secrets and directories automatically on first start.
