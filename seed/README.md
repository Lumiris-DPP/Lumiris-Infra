# seed/

Comptes nommés de production, appliqués une fois après la première migration
Flyway. Idempotent : un compte déjà présent n'est jamais écrasé, donc son mot de
passe survit à une réexécution.

## Fichiers

- `001_accounts.sql` — les quatre comptes (`ADMIN`, `REPAIRER`, `ARTISAN`,
  `CONSUMER`) plus le profil artisan associé, KYB pré-validé.
- `apply-seed.sh` — génère les mots de passe, applique le SQL, affiche les
  identifiants une seule fois.

## Exécution

```bash
./seed/apply-seed.sh prod    # lit prod/.env.prod
./seed/apply-seed.sh local   # lit local/.env
```

Le script parle à `psql` **dans le conteneur `lumiris-postgres`** : en prod la
base n'expose aucun port hôte, c'est le seul chemin d'accès. Il faut donc le
lancer depuis le serveur (ou via `ansible`), stack démarrée.

Si `prod/.env.prod` est absent, le déchiffrer d'abord :

```bash
sops -d --input-type dotenv --output-type dotenv prod/secrets/prod.env.sops > prod/.env.prod
```

## Identités

Adresses et noms par défaut, surchargeables par l'environnement :

| Rôle       | Variable email        | Défaut                    | Variable nom         | Défaut         |
| ---------- | --------------------- | ------------------------- | -------------------- | -------------- |
| `ADMIN`    | `SEED_ADMIN_EMAIL`    | `contact@lumiris.eu`      | `SEED_ADMIN_NAME`    | `Juba Aitadda` |
| `REPAIRER` | `SEED_REPAIRER_EMAIL` | `gaoubak@gmail.com`       | `SEED_REPAIRER_NAME` | `Kader`        |
| `ARTISAN`  | `SEED_ARTISAN_EMAIL`  | `adrien2098@hotmail.fr`   | `SEED_ARTISAN_NAME`  | `Adrien`       |
| `CONSUMER` | `SEED_CONSUMER_EMAIL` | `rijenththedon@gmail.com` | `SEED_CONSUMER_NAME` | `Rijenth`      |

`SEED_ARTISAN_SIRET` surcharge le SIRET du profil artisan.

Les adresses sont forcées en minuscules, côté script et côté SQL : `AuthService.normalizeEmail`
applique `trim().toLowerCase()` avant toute recherche, donc une majuscule stockée telle quelle
rendrait le compte impossible à connecter.

## Mots de passe

20 caractères alphanumériques tirés de `/dev/urandom`, hachés par `pgcrypto`
(`crypt(..., gen_salt('bf', 10))` → `$2a$`, la variante attendue par
`BCryptPasswordEncoder`). Ils ne transitent par aucun fichier : le script les
affiche puis les oublie. À ranger dans un gestionnaire de mots de passe
immédiatement, et à faire changer par chaque titulaire à la première connexion.

Une réexécution n'écrase rien : les comptes déjà présents sont signalés
`(compte préexistant)` au lieu d'un mot de passe. Pour réinitialiser un mot de
passe, supprimer la ligne `users` correspondante puis relancer.

## Ce que le seed ne fait pas

L'artisan est créé **sans abonnement**. La création de passeports exige un
abonnement ATELIER actif (`QuotaService`), donc le titulaire doit passer par le
Checkout Stripe. C'est volontaire : l'abonnement est un objet Stripe, le
fabriquer en base créerait un état que le webhook ne saurait pas réconcilier.
