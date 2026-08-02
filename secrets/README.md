# secrets/

Two-level secret strategy:

- **sops + age** for _bootstrap_ secrets (the credentials needed to talk to
  Infisical and Cloudflare in the first place). These live in this directory,
  encrypted with the age recipients listed in [`../.sops.yaml`](../.sops.yaml).
- **Infisical** for _runtime_ secrets (DB URLs, API keys, JWT secrets, …).
  Pulled by the VPS at compose-up time via `infisical run -- docker compose ...`.

The split exists because Infisical itself needs credentials to be reachable —
those credentials are the only thing that lives in the repo (encrypted), so
this directory is small by design.

## Layout

```text
secrets/
├── README.md                  # this file
├── prod.env.sops.yaml.example # bootstrap secrets for prod (encrypt before commit)
├── dev.env.sops.yaml.example  # minimal, rarely used
└── how-to-add-recipient.md    # rotating age keys + onboarding a new maintainer
```

## Per-maintainer setup

1. Generate your age key:

   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

   Then export `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` in your shell
   profile.

2. Share your **public** key with an existing maintainer; they add it to
   `../.sops.yaml` and re-encrypt the secrets (`sops updatekeys secrets/*.yaml`).

3. Verify decryption: `sops -d secrets/prod.env.sops.yaml | head -3`.

## Editing a secret

```bash
sops secrets/prod.env.sops.yaml
```

Saves back encrypted in place.

## Helper scripts

- [`../scripts/secrets-encrypt.sh`](../scripts/secrets-encrypt.sh) — encrypt all
  cleartext `*.sops.yaml` in `secrets/` (no-op if already encrypted).
- [`../scripts/secrets-decrypt.sh`](../scripts/secrets-decrypt.sh) — decrypt to
  stdout (or to a chosen path with `-o`). Refuses if `SOPS_AGE_KEY_FILE` is unset.
- [`../scripts/secrets-rotate.sh`](../scripts/secrets-rotate.sh) — `sops updatekeys`
  on every encrypted file after a recipient change.

## Hard rules

- Never commit a plaintext `*.sops.yaml` (the `*.sops.yaml.example` files in
  this directory are _templates_ — they don't contain real secrets).
- Never paste a private age key anywhere except `~/.config/sops/age/keys.txt`
  with mode `0600`.
- Rotate the prod recipients (`.sops.yaml`) whenever a maintainer leaves —
  see `how-to-add-recipient.md`.
