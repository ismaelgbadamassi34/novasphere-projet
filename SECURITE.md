# SECURITE.md — NovaSphere

Registre de sécurité du projet : où vivent les secrets, quels droits ont les instances et la CI, et ce qu'a donné le scan de sécurité.

> Contexte : l'intervenant a autorisé un compte AWS du projet (compte `725800966484`, région `eu-west-3`, Paris) à la place du Learner Lab. On peut donc créer de vrais rôles IAM et un fournisseur OIDC.

## 1. Les secrets et où ils vivent

| Secret | Où il vit | Qui l'écrit | Qui le lit |
|---|---|---|---|
| Secret applicatif dev | Parameter Store `/novasphere/dev/app-secret` (SecureString, chiffré par KMS) | Terraform (`envs/dev/secrets.tf`) | Les instances dev, au démarrage |
| Secret applicatif prod | Parameter Store `/novasphere/prod/app-secret` (SecureString) | Terraform (`envs/prod/secrets.tf`) | Les instances prod, au démarrage |
| Valeur source du secret | Secrets GitHub du dépôt `APP_SECRET_DEV` / `APP_SECRET_PROD` | Le propriétaire du dépôt, à la main | La CI, via `TF_VAR_app_secret` |

Le secret suit ce chemin, sans jamais apparaître en clair :

1. **GitHub** : la valeur est un secret du dépôt. GitHub la masque dans les logs (`***`).
2. **CI → Terraform** : elle arrive par la variable d'environnement `TF_VAR_app_secret`.
3. **Terraform** : la variable `app_secret` est déclarée `ephemeral = true` et `sensitive = true`, sans valeur par défaut. Terraform ne la garde pas entre deux opérations.
4. **AWS** : elle est passée à l'argument en écriture seule `value_wo` de `aws_ssm_parameter`. Elle est envoyée à AWS mais **jamais écrite dans le tfstate ni dans le fichier de plan**. Seul `value_wo_version` est stocké dans le state : on l'incrémente pour réécrire le secret.
5. **Instance** : `bootstrap.sh` reçoit le **chemin** du secret par `templatefile`. Le chemin n'est pas un secret. Le script lit la valeur avec `aws ssm get-parameter --with-decryption` grâce au profil IAM de l'instance, puis l'écrit dans `/etc/novasphere/secret` (droits 600, dossier 700).
6. **Page web** : elle affiche seulement `Secret chargé : oui` et une empreinte tronquée (`sha256sum | cut -c1-8`), **jamais la valeur**.

Vérifications :

```bash
terraform state pull | grep -i "app-secret"   # seuls le nom et la version apparaissent, pas la valeur
git log -p --all | grep -iE "secret|password|AKIA"   # aucune valeur dans l'historique
```

La preuve sur l'instance se fait par Session Manager, sans afficher la valeur : `sudo stat /etc/novasphere/secret`.

Ce qui n'est **jamais** commité : `terraform.tfvars`, `*.tfstate`, `.terraform/`, `*.pem`, `.env`. Le `.gitignore` les exclut.

## 2. Droits IAM des instances (appliqués)

Chaque environnement a son propre rôle (`envs/<env>/iam.tf`), attaché via un profil d'instance :

- `novasphere-dev-web` : `ssm:GetParameter` sur `arn:aws:ssm:eu-west-3:725800966484:parameter/novasphere/dev/*` uniquement ;
- `novasphere-prod-web` : `ssm:GetParameter` sur `.../parameter/novasphere/prod/*` uniquement ;
- `AmazonSSMManagedInstanceCore` (politique gérée AWS), pour Session Manager, sans SSH.

**Une instance dev ne peut pas lire le secret de prod**, et inversement.

Le déchiffrement utilise la clé gérée par AWS `aws/ssm`. Sa politique autorise le déchiffrement aux principaux du compte quand la demande passe par SSM. Aucune permission `kms:Decrypt` supplémentaire n'est donc nécessaire.

Politique idéale complète d'une instance dev :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:eu-west-3:725800966484:parameter/novasphere/dev/*"
    }
  ]
}
```

Avec en plus `AmazonSSMManagedInstanceCore`. Avec une clé KMS dédiée (voir CKV_AWS_337), il faudrait ajouter `kms:Decrypt` sur cette clé, avec la condition `kms:ViaService = ssm.eu-west-3.amazonaws.com`.

## 3. Réseau et instances

- **SG de l'ALB** : entrée HTTP 80 depuis Internet, sortie uniquement vers le SG des instances.
- **SG des instances** : entrée HTTP 80 **uniquement depuis le SG de l'ALB** (référence de SG, pas de CIDR). **Aucun port SSH ouvert.** Sortie limitée à 80 et 443 (paquets, SSM).
- **IMDSv2 exigé** : `http_tokens = "required"` et `http_put_response_hop_limit = 1` dans le Launch Template. Ça bloque le vol des identifiants du rôle par une requête SSRF à l'IMDSv1.
- **ALB** : `drop_invalid_header_fields = true`.

## 4. Authentification de la CI : identifiants de session ou OIDC

| | Identifiants de session (Learner Lab) | OIDC (notre compte) |
|---|---|---|
| Ce qui est stocké dans GitHub | 3 valeurs (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) | Rien, seulement l'ARN du rôle (pas un secret) |
| Durée | 4 h, à recopier à chaque Start Lab | Jeton de quelques minutes, émis à chaque run |
| Risque | Tout collaborateur peut les exfiltrer en modifiant un workflow dans sa branche | Le rôle ne fait confiance qu'à ce dépôt (condition sur le claim `sub`) |
| Fonctionnement | La CI se présente avec les clés | GitHub signe un jeton OIDC ; AWS le vérifie (`sts:AssumeRoleWithWebIdentity`) et délivre des identifiants temporaires |

Mise en place : fournisseur OIDC `token.actions.githubusercontent.com`, rôle CI dont la relation d'approbation exige `aud = sts.amazonaws.com` et `sub = repo:ismaelgbadamassi34/novasphere-projet:*`. Le workflow a `permissions: id-token: write, contents: read, pull-requests: write`, et n'utilise jamais `pull_request_target`.

> À COMPLÉTER quand le rôle sera créé : ARN du rôle, valeur exacte de la condition `sub`, permissions du rôle.

## 5. Réglages du dépôt

- Dépôt public. Collaborateurs : les membres de l'équipe et l'intervenant uniquement, car un collaborateur peut lire les secrets de la CI.
- Protection de `main` : PR obligatoire avec une approbation, approbations annulées par un nouveau push, pas de force-push, règle appliquée aussi aux administrateurs.
- Environnement GitHub `prod` avec relecteurs requis : l'apply de prod attend une approbation.
- Travail par branches, jamais par fork : un workflow lancé depuis un fork ne reçoit pas les secrets.

## 6. Scan de sécurité (checkov 3.4.11)

Commandes :

```bash
pip install checkov
checkov -d envs/dev                              # projet
checkov -d ../terraform-aws-novasphere-web       # module
```

Résultat initial : projet 20 checks réussis / 3 en échec ; module 38 réussis / 10 en échec.

| Check | Ressource | Décision | Justification |
|---|---|---|---|
| CKV_AWS_337 — SSM sans clé KMS du client | `aws_ssm_parameter.app_secret` | Accepté | Chiffrement KMS assuré par la clé gérée `aws/ssm`. Une clé dédiée (environ 1 $/mois chacune) isolerait dev et prod au niveau KMS ; l'isolation est déjà faite par IAM (chemin par environnement). |
| CKV_TF_1 — source de module sans hash de commit | `module.web`, `module.vpc` | Accepté | Le cahier des charges impose un appel par tag (`ref=vX.Y.Z`). Les tags du module ne sont jamais modifiés après publication. Le VPC est épinglé par contrainte de version du registre et le `.terraform.lock.hcl` fige le provider. |
| CKV_AWS_260 — port 80 ouvert à 0.0.0.0/0 | `alb_http` | Accepté | C'est le point d'entrée public du site. Seul l'ALB est exposé, pas les instances. |
| CKV_AWS_260 | `web_from_alb` | Faux positif | La règle référence le SG de l'ALB (`referenced_security_group_id`), pas 0.0.0.0/0. |
| CKV_AWS_2, CKV2_AWS_20, CKV_AWS_103, CKV_AWS_378 — pas de HTTPS ni de TLS | listener, target group | Accepté | Pas de nom de domaine, donc pas de certificat ACM public. L'extension HTTPS n'est pas retenue (voir CADRAGE.md). Le trafic ALB → instances reste dans le VPC. |
| CKV_AWS_88 — IP publique sur les instances | `aws_launch_template.web` | Accepté | Imposé par le cahier des charges : subnets publics **sans NAT Gateway** (coût). Les instances restent injoignables directement : leur SG n'accepte que le SG de l'ALB, sans SSH. |
| CKV_AWS_150 — pas de protection contre la suppression | `aws_lb.this` | Accepté | L'infrastructure est détruite à la fin de chaque session de travail (`terraform destroy`). La protection bloquerait ce destroy. |
| CKV_AWS_91 — pas de logs d'accès ALB | `aws_lb.this` | Accepté | Demanderait un bucket S3 de logs ; hors périmètre du socle. Piste d'amélioration. |
| CKV2_AWS_28 — ALB sans WAF | `aws_lb.this` | Accepté | Coût et périmètre ; piste d'amélioration pour une vraie production. |

## 7. Vérification « aucun secret nulle part »

| Endroit | Comment on l'a vérifié | Résultat |
|---|---|---|
| Code | `grep` sur le dépôt, aucune valeur par défaut sur `app_secret` | OK |
| tfstate | `terraform state pull`, la valeur n'y est pas (`value_wo`) | À vérifier après le premier apply |
| Script de démarrage | `bootstrap.sh` ne contient que le chemin SSM | OK |
| Historique Git | `git log -p --all` filtré | OK |
| Logs de CI | Lecture d'un run plan et apply : le secret est masqué | À vérifier après le premier run |
